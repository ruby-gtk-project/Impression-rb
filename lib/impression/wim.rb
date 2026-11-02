# frozen_string_literal: true

require "fiddle"

module Impression
  # Wim splits a Windows install image into FAT32-sized .swm parts.
  #
  # Ported from upstream's src/flash/wim.rs, which hand-writes an FFI to
  # libwim (wimlib) and splits in-process rather than shelling out; the same
  # library is bound here through Fiddle. wimlib's progress callback is what
  # makes the split cancellable: returning ABORT from it stops the write and
  # wimlib_split reports WIMLIB_ERR_ABORTED_BY_PROGRESS.
  module Wim
    # Raised when the user stops the write mid-split.
    class Cancelled < StandardError; end

    # Raised for every other libwim failure, carrying the code wimlib gave.
    class Failed < StandardError; end

    # Just under FAT32's 4 GiB-per-file limit, for the fewest parts. Matches
    # Rufus, as upstream notes.
    PART_SIZE = 4094 * 1024 * 1024

    # Values from wimlib.h.
    ERR_SUCCESS = 0
    ERR_ABORTED_BY_PROGRESS = 76
    STATUS_CONTINUE = 0
    STATUS_ABORT = 1

    # Lib binds the five libwim entry points the split needs.
    module Lib
      SONAMES = %w[libwim.so.15 libwim.so].freeze

      PROGRESS_FUNC = [
        Fiddle::TYPE_INT,
        [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
      ].freeze

      SIGNATURES = {
        wimlib_global_init:                [[Fiddle::TYPE_INT], Fiddle::TYPE_INT],
        wimlib_open_wim:                   [
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT,
        ],
        wimlib_split:                      [
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT],
          Fiddle::TYPE_INT,
        ],
        wimlib_free:                       [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID],
        wimlib_register_progress_function: [
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_VOID,
        ],
      }.freeze

      def self.handle
        @handle ||= SONAMES.filter_map { |soname| dlopen(soname) }.first ||
          raise(LoadError, "libwim is not installed (tried #{SONAMES.join(", ")})")
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

    # Splits input into install.swm, install2.swm, ... next to output, each
    # under FAT32's 4 GiB-per-file limit. The block is polled by wimlib's
    # progress callback and must answer whether the write is still wanted;
    # upstream hands the same question across as a shared AtomicBool because
    # its callback cannot capture.
    def self.split(input, output, &running)
      case Lib.wimlib_global_init(0)
      when ERR_SUCCESS
        split_opened(input, output, &running)
      else
        raise Failed, "wimlib_global_init failed"
      end
    end

    # The closure is held in a local for the whole call: wimlib keeps only the
    # raw function pointer, so nothing else would stop Ruby collecting it
    # mid-split.
    def self.split_opened(input, output, &running)
      wim = open_wim(input)
      callback = progress_callback(&running)
      Lib.wimlib_register_progress_function(wim, callback.to_i, nil)
      code = Lib.wimlib_split(
        wim,
        output.to_s,
        PART_SIZE,
        0,
      )
      Lib.wimlib_free(wim)
      finish(code)
    end

    # wimlib_open_wim writes the WIMStruct* into an out-parameter, so the call
    # takes a pointer-sized scratch cell and reads it back.
    def self.open_wim(input)
      out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
      code = Lib.wimlib_open_wim(input.to_s, 0, out)
      case code
      when ERR_SUCCESS
        out.ptr
      else
        raise Failed, "wimlib_open_wim failed (code #{code})"
      end
    end

    # Aborts the split as soon as the caller stops wanting it.
    def self.progress_callback(&running)
      Fiddle::Closure::BlockCaller.new(*Lib::PROGRESS_FUNC) do |_type, _info, _context|
        case running.call
        when true
          STATUS_CONTINUE
        else
          STATUS_ABORT
        end
      end
    end

    def self.finish(code)
      case code
      when ERR_SUCCESS
        nil
      when ERR_ABORTED_BY_PROGRESS
        raise Cancelled, "operation was cancelled"
      else
        raise Failed, "wimlib_split failed (code #{code})"
      end
    end
  end
end
