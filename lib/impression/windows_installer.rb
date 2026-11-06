# frozen_string_literal: true

require "fileutils"

require_relative "udisks_bus"
require_relative "flash_status"
require_relative "udf"
require_relative "wim"

module Impression
  # WindowsInstaller builds a UEFI-bootable Windows installer USB.
  #
  # Ported from upstream's src/flash/windows_installer.rs. A Windows ISO cannot
  # be raw-copied — it carries no hybrid boot record, and its install.wim
  # exceeds FAT32's 4 GiB file limit — so the ISO's UDF filesystem is read with
  # libudf, the oversized install image is split with libwim, and a single GPT
  # FAT32 partition is built and filled. #flash answers false for anything that
  # is not a Windows installer, leaving the drive untouched so the caller falls
  # back to a raw write.
  #
  # Two things differ from upstream and only those two. Upstream formats and
  # fills the staged image in-process with the `fatfs` crate, which has no Ruby
  # counterpart, so the image file — still a plain unmounted file, built on
  # local disk and then cloned to the stick in large sequential blocks exactly
  # as upstream does it — is formatted with mkfs.vfat and filled with mcopy,
  # the same way the port already decompresses with xzcat. And udisks exposes
  # no partition-table signal through these bindings, so the wait for the table
  # to appear after the GPT format polls the object's interfaces instead of
  # watching InterfacesAdded.
  class WindowsInstaller
    # Raised for an installer build that failed on its own terms, as upstream's
    # WindowsInstallerFailed.
    class Failed < StandardError; end

    # FAT32 cannot store a single file of 4 GiB or larger. Windows install
    # images regularly exceed this, so they must be split.
    FAT32_MAX_FILE_SIZE = (4 * 1024 * 1024 * 1024) - 1

    # Headroom added to the content size when sizing the partition, covering
    # FAT tables, directory entries and cluster slack. Far more than needed, so
    # the build never runs out of space.
    PARTITION_MARGIN = 256 * 1024 * 1024

    # What marks a source as a Windows installer, and what has to be split.
    INSTALL_IMAGES = %w[install.wim install.esd].freeze

    # How long to wait for udisks to expose the partition table after the GPT
    # format, and how often to look.
    SETTLE_TIMEOUT = 15.0
    SETTLE_INTERVAL = 0.3

    # An automounter can grab a freshly formatted filesystem a second or two
    # after it appears, and writing the raw device while the kernel's FAT driver
    # holds it corrupts the filesystem, so the unmount is repeated until a full
    # cycle sees no mount points.
    UNMOUNT_ATTEMPTS = 10

    # FAT32 volume label fallback, when the source ISO's label leaves nothing
    # usable.
    DEFAULT_LABEL = "INSTALLER"

    def initialize(request:, source_path:)
      @request = request
      @source_path = source_path.to_s
    end

    # Builds the installer and answers true, or answers false without touching
    # the destination when the source is not a Windows ISO.
    def flash
      case iso?
      when false
        false
      else
        attempt
      end
    end

    private

      attr_reader :request, :source_path

      # .img/.raw images are always raw-written; only ISOs are probed.
      def iso? = File.basename(source_path).downcase.include?(".iso")

      def attempt
        label = extract_iso
        case label
        when nil
          clear_work_dir
          false
        else
          build_and_clean(label)
          true
        end
      end

      # The scratch tree goes away whether the build succeeded or failed.
      def build_and_clean(label)
        build(label)
      ensure
        clear_work_dir
      end

      def build(label)
        volume = fat_label(label)
        split_oversized_install_image
        content_total = dir_byte_total(work_dir)
        case content_total.zero?
        when true
          raise Failed, "extracted ISO was empty"
        end

        request.publish(FlashStatus.active(:partition, Progress.pulse))
        request.check_running
        stage_and_clone(
          prepare_fat32_partition(volume, partition_size_for(content_total)),
          volume,
          content_total,
        )
      end

      # Extracts the ISO into a fresh work directory when it is a Windows
      # installer and answers its volume label; nil means it is not one.
      def extract_iso
        request.publish(FlashStatus.active(:extract, Progress.pulse))
        image = open_image
        case image
        when nil
          nil
        else
          extract_from(image)
        end
      end

      # A non-UDF image — a Linux ISO9660 one, say — simply is not Windows.
      def open_image
        Udf::Image.open(source_path)
      rescue Udf::OpenError
        nil
      end

      def extract_from(image)
        case INSTALL_IMAGES.any? { |name| image.path?("sources/#{name}") }
        when false
          nil
        else
          extract_tree(image)
        end
      ensure
        image.close
      end

      def extract_tree(image)
        image.volume_label.to_s.tap do |_label|
          reset_work_dir
          image.extract_all(
            work_dir,
            on_progress: ->(done, total) { report_extract(done, total) },
            cancelled:   -> { !request.running? },
          )
        end
      end

      def report_extract(done, total)
        request.publish(FlashStatus.active(:extract, Progress.of(done, total)))
      end

      # Splits sources/install.wim (or .esd) into .swm parts in place when it
      # exceeds the FAT32 file-size limit, then removes the oversized original:
      # Windows Setup loads the parts, and the original must not remain.
      def split_oversized_install_image
        INSTALL_IMAGES.each do |name|
          image = File.join(work_dir, "sources", name)
          case oversized?(image)
          when true
            split_install_image(image)
          end
        end
      end

      def oversized?(image)
        File.file?(image) && File.size(image) > FAT32_MAX_FILE_SIZE
      end

      def split_install_image(image)
        request.publish(FlashStatus.active(:process_image, Progress.pulse))
        Wim.split(image, File.join(work_dir, "sources", "install.swm")) { request.running? }
        File.delete(image)
      end

      # A request at or above the device size means "use the whole drive", as
      # upstream's partition_arg of 0; otherwise the rest of the drive is left
      # unallocated, exactly like a raw image write.
      def partition_size_for(content_total)
        requested = content_total + PARTITION_MARGIN
        case requested >= device_size
        when true
          0
        else
          requested
        end
      end

      def device_size
        Udisks.property(request.device_path, Udisks::BLOCK_INTERFACE, "Size").to_i
      end

      # Wipes the destination to a GPT disk holding a single FAT32 partition of
      # size bytes (0 means fill the drive) and answers the new partition's
      # object path. The partition and the filesystem are both named label.
      def prepare_fat32_partition(volume, size)
        Udisks.call!(
          request.device_path,
          Udisks::BLOCK_INTERFACE,
          "Format",
          GLib::Variant.parse("('gpt', {})", "(sa{sv})"),
        )
        wait_for_partition_table
        Udisks.call!(
          request.device_path,
          Udisks::PARTITION_TABLE_INTERFACE,
          "CreatePartitionAndFormat",
          create_partition_arguments(volume, size),
        ).to_a.first
      end

      # The label is sanitised to FAT's own alphabet before it gets here, so it
      # carries nothing the variant text format would reinterpret.
      def create_partition_arguments(volume, size)
        GLib::Variant.parse(
          "(0, #{size}, '', '#{volume}', {}, 'vfat', " \
            "{'label': <'#{volume}'>, 'update-partition-type': <true>})",
          "(ttssa{sv}sa{sv})",
        )
      end

      def wait_for_partition_table
        deadline = monotonic + SETTLE_TIMEOUT
        until partition_table?
          case monotonic >= deadline
          when true
            raise Failed, "udisks exposed no partition table on #{request.device_path}"
          end
          sleep(SETTLE_INTERVAL)
        end
      end

      def partition_table?
        Udisks.interfaces_of(request.device_path).include?(Udisks::PARTITION_TABLE_INTERFACE)
      end

      # Builds the filesystem into a partition-sized image on local disk, then
      # clones it onto the freshly prepared partition with the same copy the raw
      # write uses: mcopy's many tiny scattered metadata writes are slow sent
      # synchronously to a stick and free in the page cache on local disk.
      def stage_and_clone(partition, volume, content_total)
        partition_size = Udisks.property(partition, Udisks::BLOCK_INTERFACE, "Size").to_i
        request.publish(FlashStatus.active(:build_image, Progress.pulse))
        build_fat_image(partition_size, volume, content_total)
        ensure_unmounted(partition)
        request.check_running
        request.copy_to_device(image_path, partition)
      ensure
        FileUtils.rm_f(image_path)
      end

      def build_fat_image(partition_size, volume, content_total)
        FileUtils.mkdir_p(File.dirname(image_path))
        File.open(image_path, "wb") { |file| file.truncate(partition_size) }
        run(
          "mkfs.vfat",
          "-F",
          "32",
          "-n",
          volume,
          image_path,
        )
        pack_image(content_total)
      end

      # Each top-level entry is copied in on its own and deleted once packed, so
      # the scratch directory never holds the whole installer twice — upstream's
      # delete_packed — and the progress bar advances between entries.
      def pack_image(content_total)
        Dir.children(work_dir).sort.inject(0) do |done, name|
          request.check_running
          entry = File.join(work_dir, name)
          packed = done + dir_byte_total(entry)
          run(
            "mcopy",
            "-s",
            "-o",
            "-Q",
            "-i",
            image_path,
            entry,
            "::",
          )
          FileUtils.rm_rf(entry)
          request.publish(FlashStatus.active(:build_image, Progress.of(packed, content_total)))
          packed
        end
      end

      # Unmounts the partition and confirms it stays unmounted, defeating the
      # desktop automount race.
      def ensure_unmounted(partition)
        UNMOUNT_ATTEMPTS.times do
          Udisks.call(
            partition,
            Udisks::FILESYSTEM_INTERFACE,
            "Unmount",
            GLib::Variant.parse("({'force': <true>},)", "(a{sv})"),
          )
          # Let a pending automount actually fire so it can be seen and undone.
          sleep(SETTLE_INTERVAL)
          case mounted?(partition)
          when false
            break
          end
        end
      end

      def mounted?(partition)
        !Udisks.property(partition, Udisks::FILESYSTEM_INTERFACE, "MountPoints").to_a.empty?
      end

      # Runs one of the filesystem tools, failing loudly with whatever it said.
      # MTOOLS_SKIP_CHECK keeps mcopy from refusing an image whose geometry it
      # cannot match to a floppy or a disk it knows.
      def run(*command)
        reader, writer = IO.pipe
        pid = Process.spawn({"MTOOLS_SKIP_CHECK" => "1"}, *command, out: writer, err: writer)
        writer.close
        output = reader.read
        reader.close
        check_status(command.first, output, Process.waitpid2(pid).last)
      end

      def check_status(tool, output, status)
        case status.success?
        when false
          raise Failed, "#{tool} failed: #{output.strip}"
        end
      end

      # Total size in bytes of every regular file at or under path.
      def dir_byte_total(path)
        case File.directory?(path)
        when true
          Dir.children(path).sum { |name| dir_byte_total(File.join(path, name)) }
        else
          File.size(path)
        end
      end

      # FAT32 volume label from the source ISO label: uppercase ASCII, at most
      # 11 characters, matching what Rufus does.
      def fat_label(source)
        cleaned = source.to_s.upcase.chars.grep(/\A[A-Z0-9_-]\z/).first(11).join
        case cleaned
        when ""
          DEFAULT_LABEL
        else
          cleaned
        end
      end

      def reset_work_dir
        clear_work_dir
        FileUtils.mkdir_p(work_dir)
      end

      def clear_work_dir = FileUtils.rm_rf(work_dir)

      def work_dir = File.join(request.cache_dir, "impression-windows")

      def image_path = File.join(request.cache_dir, "impression-windows.img")

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
