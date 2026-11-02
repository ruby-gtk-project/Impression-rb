# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "net/http"
require "uri"

require_relative "distro_release"
require_relative "xml"

module Impression
  # Online fetches osinfo-db and turns it into the two lists the welcome page
  # shows, one per architecture.
  #
  # Ported from upstream's src/online.rs: resolve the latest osinfo-db archive
  # from db.libosinfo.org, download it, extract only the requested distros'
  # directories with tar, then read each release's XML for its name, version
  # and per-architecture media URLs.
  module Online
    LATEST_URL = "https://db.libosinfo.org/latest.json"

    # Upstream's TWO_YEARS, the same leap-year-ignoring approximation.
    TWO_YEARS = 365 * 2

    ARCHITECTURES = %w[x86_64 aarch64].freeze

    MAX_REDIRECTS = 5

    # The archive URL of the newest osinfo-db release, or nil when the request
    # fails — which the window reads as "offline".
    def self.osinfo_db_url
      JSON.parse(get(LATEST_URL)).dig("release", "archive")
    rescue StandardError, JSON::ParserError => e
      warn "Failed to resolve the osinfo-db url: #{e.message}"
      nil
    end

    # Downloads and reads the database, returning [amd_releases, arm_releases],
    # or nil when any step fails.
    def self.collect(latest_url, downloadable_distros)
      database_dir(latest_url, downloadable_distros).then do |directory|
        case directory
        when nil
          nil
        else
          releases_of(directory, downloadable_distros)
        end
      end
    end

    # Extracts the requested distros out of the archive into the cache
    # directory, returning that directory.
    def self.database_dir(latest_url, downloadable_distros)
      directory = cache_dir
      FileUtils.mkdir_p(directory)
      archive = File.join(directory, "db.tar.xz")
      case download(latest_url, archive)
      when false
        nil
      else
        extract(archive, directory, patterns_for(downloadable_distros))
      end
    rescue SystemCallError => e
      warn "Failed to prepare the osinfo-db cache: #{e.message}"
      nil
    end

    def self.cache_dir
      File.join(
        ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache")),
        "impression-rb",
        "osinfo-db",
      )
    end

    # The same `*/os/<distro>` wildcards upstream passes to tar, so only the
    # requested distros are unpacked.
    def self.patterns_for(downloadable_distros)
      downloadable_distros.map { |distro, _must_contain, _invert| "*/os/#{distro}" }.uniq
    end

    def self.extract(archive, directory, patterns)
      arguments = [
        "-xf",
        archive,
        "--directory",
        directory,
        "--strip-components=2",
        "--wildcards",
        *patterns,
      ]
      case system("tar", *arguments)
      when true
        directory
      else
        warn "Failed to extract #{archive}"
        nil
      end
    end

    def self.releases_of(directory, downloadable_distros)
      amd = []
      arm = []
      downloadable_distros.each do |distro, must_contain, invert|
        for_distro(
          directory,
          distro,
          must_contain,
          invert,
        ).then do |(found_amd, found_arm)|
          amd.concat(found_amd)
          arm.concat(found_arm)
        end
      end
      [amd, arm]
    end

    # One distro's releases, deduplicated by variant the way upstream's
    # HashMap<Option<String>, DistroRelease> is, then sorted.
    def self.for_distro(directory, distro, must_contain, invert)
      amd = {}
      arm = {}
      Dir.glob(File.join(directory, distro, "*")).sort.each do |file|
        releases_in(file, must_contain, invert).each do |architecture, release|
          case architecture
          when "x86_64"
            amd[release.variant] = release
          else
            arm[release.variant] = release
          end
        end
      end
      [amd.values.sort, arm.values.sort]
    end

    # Upstream's parse_xml_file: [architecture, DistroRelease] pairs for one
    # release's XML, empty for a file that is irrelevant or unreadable.
    def self.releases_in(file, must_contain, invert)
      os = os_element(file)
      case os
      when nil
        []
      else
        media_releases(os, must_contain, invert)
      end
    end

    def self.os_element(file)
      case File.file?(file)
      when false
        nil
      else
        Xml.parse(File.read(file))&.descendant("os")
      end
    rescue SystemCallError => e
      warn "Failed to read #{file}: #{e.message}"
      nil
    end

    def self.media_releases(os, must_contain, invert)
      case relevant?(os)
      when false
        []
      else
        name = os.child_text("name")
        case name
        when nil, ""
          []
        else
          releases_for_media(
            os,
            name,
            must_contain,
            invert,
          )
        end
      end
    end

    def self.releases_for_media(os, name, must_contain, invert)
      variants = variants_of(os)
      version = os.child_text("version")

      media_of(os).filter_map do |media|
        variant_name = variant_name_of(media, variants, name)
        case matches?(variant_name, must_contain, invert)
        when false
          nil
        else
          [media["arch"], release_for(
            media,
            variants,
            variant_name,
            version,
          )
]
        end
      end
    end

    def self.release_for(media, variants, variant_name, version)
      DistroRelease.new(
        name:    variant_name,
        version: version,
        url:     media.child_text("url"),
        variant: variants.key(variant_name),
      )
    end

    def self.media_of(os)
      os.each_child("media").select do |media|
        ARCHITECTURES.include?(media["arch"]) && !media.child_text("url").to_s.empty?
      end
    end

    def self.variants_of(os)
      os.each_child("variant").to_h do |variant|
        [variant["id"], variant.child_text("name")]
      end.reject { |id, variant_name| id.nil? || variant_name.nil? }
    end

    def self.variant_name_of(media, variants, default_name)
      variants.fetch(media.child("variant")&.[]("id"), default_name)
    end

    # Upstream's matches_must_contains: no constraint matches everything, and
    # `invert` flips the sense of the one that is there.
    def self.matches?(name, must_contain, invert)
      case must_contain
      when nil, ""
        true
      else
        name.to_s.include?(must_contain) != invert
      end
    end

    # Upstream's is_relevant_for_current_day: prereleases are never shown, a
    # dated release has to be within two years, and an undated one has to be
    # rolling.
    def self.relevant?(os)
      status = os.child_text("release-status")
      date = parse_date(os.child_text("release-date"))
      case status
      when "prerelease"
        false
      else
        current?(date, status)
      end
    end

    def self.current?(date, status)
      case date
      when nil
        status == "rolling"
      else
        date + TWO_YEARS >= Date.today
      end
    end

    def self.parse_date(text)
      parts = text.to_s.split("-").map { |part| Integer(part, 10, exception: false) }
      case parts
      in [Integer => year, Integer => month, Integer => day]
        Date.new(year, month, day)
      else
        nil
      end
    rescue Date::Error
      nil
    end

    # Streams a URL to a path, following redirects. False on any failure.
    def self.download(url, path)
      File.open(path, "wb") do |file|
        request(url) do |response|
          response.read_body { |chunk| file.write(chunk) }
        end
      end
      true
    rescue StandardError => e
      warn "Failed to download #{url}: #{e.message}"
      false
    end

    def self.get(url)
      (+"").tap do |body|
        request(url) { |response| body << response.read_body }
      end
    end

    def self.request(url, redirects = MAX_REDIRECTS, &block)
      uri = URI.parse(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          handle_response(response, redirects, &block)
        end
      end
    end

    def self.handle_response(response, redirects, &block)
      case response
      when Net::HTTPRedirection
        follow(response, redirects, &block)
      when Net::HTTPSuccess
        block.call(response)
      else
        raise "unexpected response #{response.code}"
      end
    end

    def self.follow(response, redirects, &block)
      case redirects
      when 0
        raise "too many redirects"
      else
        request(response["location"], redirects - 1, &block)
      end
    end
  end
end
