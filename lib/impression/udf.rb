# frozen_string_literal: true

require "fiddle"
require "fileutils"

module Impression
  # Udf reads the UDF filesystem on a Windows install ISO: the entry list, a
  # single file, the volume label, and a full extraction of the tree.
  #
  # Ported from upstream's src/flash/udf.rs. Upstream hand-writes an FFI to
  # libcdio's libudf rather than taking a bindgen dependency; the same library
  # is bound here through Fiddle, so the port needs no C extension of its own.
  # Windows media is UDF-only because install.wim exceeds 4 GiB, which
  # libarchive cannot read.
  #
  # Ownership mirrors upstream's notes: udf_open returns a udf_t* freed by
  # udf_close, udf_get_root and udf_fopen return owned dirents freed by
  # udf_dirent_free, and a dirent from udf_opendir (or the root) is a
  # content-iteration handle that udf_readdir advances and frees once it
  # returns NULL. udf_opendir rejects the root, so the root is iterated with
  # udf_readdir directly.
  module Udf
    # Raised when the image will not open at all, which the caller reads as
    # "not a Windows ISO" rather than as a failure.
    class OpenError < StandardError; end

    # Raised when libudf refuses a read that should have succeeded.
    class ReadError < StandardError; end

    # Raised when the caller's cancellation check trips, as upstream's
    # UdfError::Cancelled.
    class Cancelled < StandardError; end

    # UDF logical block size for the media we handle.
    BLOCK_SIZE = 2048

    # Read granularity when streaming a file out (1 MiB).
    CHUNK_BLOCKS = 512

    # Lib binds the handful of libudf entry points upstream declares. The
    # prototypes' `bool` is a one-byte C type, so it crosses as a char, and
    # every dirent parameter is a plain pointer: libudf's `const` does not
    # affect the ABI.
    module Lib
      SONAMES = %w[libudf.so.0 libudf.so].freeze

      SIGNATURES = {
        udf_open:            [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        udf_close:           [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_CHAR],
        udf_get_root:        [
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_CHAR, Fiddle::TYPE_SHORT],
          Fiddle::TYPE_VOIDP,
        ],
        udf_get_volume_id:   [
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
          Fiddle::TYPE_INT,
        ],
        udf_fopen:           [[Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        udf_dirent_free:     [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_CHAR],
        udf_get_filename:    [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        udf_get_file_length: [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG_LONG],
        udf_setpos:          [[Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG], Fiddle::TYPE_CHAR],
        udf_read_block:      [
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
          Fiddle::TYPE_SSIZE_T,
        ],
        udf_readdir:         [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        udf_opendir:         [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        udf_is_dir:          [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_CHAR],
      }.freeze

      # The library is resolved by soname at load time, the way upstream links
      # it dynamically; a host without libcdio raises here and the Windows
      # path reports that it cannot run.
      def self.handle
        @handle ||= SONAMES.filter_map { |soname| dlopen(soname) }.first ||
          raise(LoadError, "libudf is not installed (tried #{SONAMES.join(", ")})")
      end

      def self.dlopen(soname)
        Fiddle.dlopen(soname)
      rescue Fiddle::DLError
        nil
      end

      def self.functions = @functions ||= {}

      def self.function(name)
        functions[name] ||= SIGNATURES.fetch(name).then do |arguments, result|
          Fiddle::Function.new(handle[name.to_s], arguments, result)
        end
      end

      SIGNATURES.each_key do |name|
        define_singleton_method(name) { |*values| function(name).call(*values) }
      end
    end

    # Entry is one listed path inside an image, as upstream's udf.rs Entry.
    class Entry
      attr_reader :path, :length

      def initialize(path:, directory:, length:)
        @path = path
        @directory = directory
        @length = length
      end

      def directory? = @directory
    end

    # File is one open file inside an image, held by its own dirent.
    class File
      def initialize(raw)
        @raw = raw
      end

      def length = Lib.udf_get_file_length(@raw)

      # Streams the whole file to io. udf_read_block returns at most one extent
      # per call and advances the image position, so this loops until the
      # declared length is reached — the multi-extent path a >4 GiB install.wim
      # exercises. The final extent is block-padded, so the write is clamped to
      # the real length.
      def read_to(io, on_progress: nil, cancelled: nil)
        total = length
        Lib.udf_setpos(@raw, 0)
        buffer = Fiddle::Pointer.malloc(CHUNK_BLOCKS * BLOCK_SIZE, Fiddle::RUBY_FREE)
        written = 0

        while written < total
          Udf.check_cancelled(cancelled)
          take = [read_chunk(buffer, total - written), total - written].min
          io.write(buffer[0, take])
          written += take
          on_progress&.call(written)
        end

        written
      end

      def close = Lib.udf_dirent_free(@raw)

      private

        def read_chunk(buffer, remaining)
          blocks = [remaining.fdiv(BLOCK_SIZE).ceil, CHUNK_BLOCKS].min
          read = Lib.udf_read_block(@raw, buffer, blocks)
          case read.positive?
          when true
            read
          else
            raise ReadError, "udf_read_block returned #{read}"
          end
        end
    end

    # Extraction is one run of Image#extract_all: where the tree is going, how
    # much of it there is, and how far it has got. Upstream carries the same
    # state in the closures it hands to extract_all.
    class Extraction
      attr_reader :dest, :cancelled

      def initialize(dest:, total:, on_progress:, cancelled:)
        @dest = dest
        @total = total
        @on_progress = on_progress
        @cancelled = cancelled
        @done = 0
      end

      # Cumulative bytes across the whole extraction, not just this file.
      def report(bytes) = @on_progress&.call(@done + bytes, @total)

      def advance(bytes) = @done += bytes
    end

    # Image is an opened UDF image.
    class Image
      def self.open(path)
        raw = Lib.udf_open(path.to_s)
        case raw.null?
        when true
          raise OpenError, "could not open UDF image: #{path}"
        else
          new(raw)
        end
      end

      def initialize(raw)
        @raw = raw
      end

      def close = Lib.udf_close(@raw)

      # The image's volume identifier (latin-1), or nil when absent. Used to
      # label the installer USB the way the source ISO is labelled.
      def volume_label
        buffer = Fiddle::Pointer.malloc(128, Fiddle::RUBY_FREE)
        written = Lib.udf_get_volume_id(@raw, buffer, 128).clamp(0, 128)
        label = buffer[0, written].split("\0").first.to_s
        label.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8).strip.then do |text|
          case text
          when ""
            nil
          else
            text
          end
        end
      end

      # Whether rel (a /-separated, case-sensitive path) exists.
      def path?(rel)
        file = open_file(rel)
        case file
        when nil
          false
        else
          file.close
          true
        end
      end

      # Opens a file by path, or nil when it does not exist.
      def open_file(rel)
        handle = root
        raw = Lib.udf_fopen(handle, rel.to_s)
        Lib.udf_dirent_free(handle)
        case raw.null?
        when true
          nil
        else
          File.new(raw)
        end
      end

      # Every entry in the image, files and directories, recursively.
      def entries
        [].tap { |collected| collect(root, "", collected) }
      end

      # Extracts the entire image into dest, recreating its directory tree.
      # on_progress is called with cumulative file bytes and the total;
      # cancelled is polled between files and chunks.
      def extract_all(dest, on_progress: nil, cancelled: nil)
        listed = entries
        files = listed.reject(&:directory?)

        listed.select(&:directory?).each do |directory|
          FileUtils.mkdir_p(::File.join(dest, directory.path))
        end

        extraction = Extraction.new(
          dest:        dest,
          total:       files.sum(&:length),
          on_progress: on_progress,
          cancelled:   cancelled,
        )
        files.each { |entry| extract_one(entry, extraction) }
      end

      private

        # The root directory as a content-iteration handle, owned by the
        # caller.
        def root
          raw = Lib.udf_get_root(@raw, 1, 0)
          case raw.null?
          when true
            raise ReadError, "udf_get_root returned NULL"
          else
            raw
          end
        end

        def extract_one(entry, extraction)
          Udf.check_cancelled(extraction.cancelled)
          target = ::File.join(extraction.dest, entry.path)
          FileUtils.mkdir_p(::File.dirname(target))
          file = open_file(entry.path)
          case file
          when nil
            raise ReadError, "file vanished: #{entry.path}"
          else
            write_out(file, target, extraction)
          end
        end

        def write_out(file, target, extraction)
          written = ::File.open(target, "wb") do |output|
            file.read_to(
              output,
              on_progress: ->(bytes) { extraction.report(bytes) },
              cancelled:   extraction.cancelled,
            ).tap { output.flush }
          end
          extraction.advance(written)
        ensure
          file.close
        end

        # Recursively collects a directory content-handle. udf_readdir advances
        # and ultimately frees the handle, so ownership is transferred in.
        def collect(handle, prefix, collected)
          loop do
            entry = Lib.udf_readdir(handle)
            case entry.null?
            when true
              break
            end

            collect_entry(entry, prefix, collected)
          end
        end

        def collect_entry(entry, prefix, collected)
          name = filename(entry)
          # The self/parent entry carries an empty file identifier.
          case name
          when "", ".", ".."
            nil
          else
            descend(entry, join(prefix, name), collected)
          end
        end

        def descend(entry, path, collected)
          directory = Lib.udf_is_dir(entry).to_i.nonzero?
          collected << Entry.new(
            path:      path,
            directory: !directory.nil?,
            length:    Lib.udf_get_file_length(entry),
          )

          case directory
          when nil
            nil
          else
            # The dirent now carries a FID, so udf_opendir accepts it and
            # returns a fresh content handle for the subdirectory.
            collect_child(Lib.udf_opendir(entry), path, collected)
          end
        end

        def collect_child(child, path, collected)
          case child.null?
          when true
            nil
          else
            collect(child, path, collected)
          end
        end

        def filename(entry)
          pointer = Lib.udf_get_filename(entry)
          case pointer.null?
          when true
            ""
          else
            pointer.to_s
          end
        end

        def join(prefix, name)
          case prefix
          when ""
            name
          else
            "#{prefix}/#{name}"
          end
        end
    end

    def self.check_cancelled(cancelled)
      case cancelled&.call
      when true
        raise Cancelled, "operation was cancelled"
      end
    end
  end
end
