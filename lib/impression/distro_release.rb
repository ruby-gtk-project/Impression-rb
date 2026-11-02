# frozen_string_literal: true

require "uri"

module Impression
  # DistroRelease is one downloadable image: the name shown in the welcome
  # page's list, the version under it, the URL it is fetched from, and the
  # osinfo-db variant id it came from.
  #
  # Ported from upstream's src/online.rs (DistroRelease). Upstream derives Ord
  # over the fields in declaration order, which is what the list is sorted by,
  # so the same ordering is spelled out in #sort_key here.
  class DistroRelease
    include Comparable

    FALLBACK_FILE_NAME = "disk-image.img"

    attr_reader :name, :version, :url, :variant

    def initialize(name:, url:, version: nil, variant: nil)
      @name = name
      @version = version
      @url = url
      @variant = variant
    end

    def sort_key = [name.to_s, version.to_s, url.to_s, variant.to_s]

    def <=>(other) = sort_key <=> other.sort_key

    # The name the save dialog offers: upstream takes the URL's last path
    # segment and falls back to a generic name when there is none.
    def file_name
      segment = URI.parse(url).path.to_s.split("/").last
      case segment
      when nil, ""
        FALLBACK_FILE_NAME
      else
        segment
      end
    rescue URI::InvalidURIError
      FALLBACK_FILE_NAME
    end
  end
end
