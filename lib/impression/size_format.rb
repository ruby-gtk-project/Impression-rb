# frozen_string_literal: true

module Impression
  # SizeFormat renders a byte count the way the device page labels it.
  #
  # Ported from upstream's src/main.rs (get_size_string): mebibytes with no
  # decimals up to 1023, then gibibytes with two.
  module SizeFormat
    MEBI = 1024 * 1024

    def self.call(bytes)
      mebi_bytes = bytes.to_i / MEBI
      case mebi_bytes
      when 0..1023
        "#{mebi_bytes}MiB"
      else
        format("%.2fGiB", mebi_bytes / 1024.0)
      end
    end
  end
end
