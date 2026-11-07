# frozen_string_literal: true

require "fileutils"
require "uri"

require_relative "udisks_bus"
require_relative "flash_status"
require_relative "online"
require_relative "windows_installer"

module Impression
  # FlashRequest writes a disk image to a drive, publishing a FlashStatus the
  # window polls once a second.
  #
  # Ported from upstream's src/flash/mod.rs (FlashRequest): resolve the source
  # — download it, or decompress an xz one — unmount whatever the drive has
  # mounted, open the block device through udisks with O_SYNC, copy it across in
  # buffered chunks, then rescan and eject.
  #
  # Upstream runs the job on its tokio runtime and shares an AtomicBool with
  # the window to cancel it; here it is a Ruby thread and a mutex-guarded flag,
  # read through #running? and cleared by #cancel.
  class FlashRequest
    # Raised when the user stops the write; upstream's ProcessStoppedByUser,
    # which it narrows out so a cancelled run reports no error.
    class Cancelled < StandardError; end

    CHUNK = 256 * 1024
    REPORT_INTERVAL = 0.25

    attr_reader :device_path

    def initialize(source:, device_path:)
      @source = source
      @device_path = device_path
      @mutex = Mutex.new
      @running = true
      @status = FlashStatus.active(source.initial_phase, Progress.of(0, 1))
    end

    def status = @mutex.synchronize { @status }

    def running? = @mutex.synchronize { @running }

    def cancel = @mutex.synchronize { @running = false }

    # The four members below are what the Windows installer path drives, as
    # upstream's windows_installer.rs calls set_status, stopped_running and
    # load_file on FlashRequest itself.
    def publish(status) = @mutex.synchronize { @status = status }

    def check_running
      case running?
      when false
        raise Cancelled
      end
    end

    def cache_dir
      File.join(
        ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache")),
        "impression-rb",
      )
    end

    # Copies source_path onto a block device, the destination drive by default
    # and the installer's partition when the Windows path asks for it.
    def copy_to_device(source_path, target = device_path)
      device = open_device(target)
      File.open(source_path, "rb") do |source|
        stream(source, device, File.size(source_path))
      end
    ensure
      device&.close
    end

    # Runs the pipeline on its own thread, as upstream spawns it onto the
    # runtime.
    def start = Thread.new { perform }

    def perform
      write
      publish(FlashStatus.done)
    rescue Cancelled
      nil
    rescue StandardError => e
      warn "Flashing process failed: #{e.message}"
      publish(FlashStatus.done(e.message))
    end

    private

      def write
        check_running
        unmount_partitions
        check_running
        source_path = prepared_source_path
        check_running
        # A Windows ISO cannot simply be raw-copied: it carries no hybrid boot
        # record and ships an install.wim larger than FAT32's 4 GiB file limit.
        # The installer path builds a bootable FAT32 USB for one and answers
        # false for anything else, so this falls back to a raw byte copy.
        case try_windows_installer(source_path)
        when false
          copy_to_device(source_path)
        end
        rescan
        eject
      end

      # The installer path raises libudf's and libwim's own cancellations, which
      # are this pipeline's Cancelled.
      def try_windows_installer(source_path)
        WindowsInstaller.new(request: self, source_path: source_path).flash
      rescue Udf::Cancelled, Wim::Cancelled
        raise Cancelled
      end

      # Upstream ignores unmount failures: a partition that was never mounted
      # is not a reason to refuse to write.
      def unmount_partitions
        Udisks.partitions_of(device_path).each { |partition| Udisks.unmount(partition) }
      end

      # Upstream's prepared_source_path: a path on disk, whatever the source is.
      def prepared_source_path
        case
        when @source.online?
          download_source
        when @source.compressed?
          extract_source
        else
          @source.path
        end
      end

      def download_source
        @source.path.to_s.tap do |path|
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "wb") do |file|
            Online.request(@source.url) { |response| save_download(response, file) }
          end
        end
      end

      def save_download(response, file)
        total = Integer(response["content-length"].to_s, exception: false)
        case total
        when nil, 0
          raise "Total size could not be determined"
        end

        downloaded = 0
        last = monotonic
        response.read_body do |chunk|
          file.write(chunk)
          downloaded = [downloaded + chunk.bytesize, total].min
          case elapsed?(last)
          when true
            publish(FlashStatus.active(:download, Progress.of(downloaded, total)))
            last = monotonic
          end
          check_running
        end

        file.flush
        file.fsync
      end

      # Upstream shells out to xzcat for the same reason: it is already there,
      # and it decompresses faster than anything in-process.
      def extract_source
        FileUtils.mkdir_p(cache_dir)
        result = File.join(cache_dir, File.basename(@source.path.to_s, ".xz"))
        publish(FlashStatus.active(:extract, Progress.pulse))
        run_xzcat(@source.path.to_s, result)
        result
      end

      def run_xzcat(input, output)
        File.open(output, "wb") do |file|
          errors, status = spawn_xzcat(input, file)
          case status.success?
          when false
            raise "XZ extraction failed: #{errors.strip}"
          end
        end
      end

      def spawn_xzcat(input, file)
        reader, writer = IO.pipe
        pid = Process.spawn(
          "xzcat",
          input,
          "-k",
          "-T0",
          out: file,
          err: writer,
        )
        writer.close
        errors = reader.read
        reader.close
        [errors, Process.waitpid2(pid).last]
      end

      # Upstream opens the device through udisks with O_SYNC, so each write
      # commits to the drive before the next one is issued instead of bursting
      # at a marginal stick, and so a sandboxed app needs no device permission
      # of its own.
      def open_device(path)
        IO.for_fd(Udisks.open_device(path), "r+b")
      end

      # A flush or sync failure here means the drive dropped writes, typically a
      # USB disconnect, so it fails rather than reporting a corrupt write as a
      # success.
      def stream(source, target, size)
        total = 0
        last = monotonic
        while (chunk = source.read(CHUNK))
          target.write(chunk)
          total += chunk.bytesize
          check_running
          case elapsed?(last)
          when true
            publish(FlashStatus.active(:copy, Progress.of(total, size)))
            last = monotonic
          end
        end

        target.flush
        target.fsync
      end

      def rescan = Udisks.rescan(device_path)

      def eject = Udisks.eject(device_path)

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def elapsed?(last) = monotonic - last >= REPORT_INTERVAL
  end
end
