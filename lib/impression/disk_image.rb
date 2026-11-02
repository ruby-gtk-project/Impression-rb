# frozen_string_literal: true

module Impression
  # DiskImage is the selected source: a file already on disk, raw or xz
  # compressed, or an image to be downloaded to a path the user picked.
  #
  # Ported from upstream's src/window.rs (Compression, DiskImage).
  class DiskImage
    attr_reader :path, :compression, :url, :name

    # A local file. Anything ending in .xz is decompressed before writing.
    def self.local(path)
      new(:local, path: path, compression: compression_of(path))
    end

    def self.compression_of(path)
      case File.extname(path.to_s)
      when ".xz"
        :xz
      else
        :raw
      end
    end

    # An online image, with the path it will be downloaded to.
    def self.online(url:, download_path:, name:)
      new(:online, url: url, path: download_path, name: name)
    end

    def initialize(kind, path: nil, compression: :raw, url: nil, name: nil)
      @kind = kind
      @path = path
      @compression = compression
      @url = url
      @name = name
    end

    def local? = @kind == :local

    def online? = @kind == :online

    def compressed? = compression == :xz

    # What the device page shows as the image's name.
    def display_name
      case @kind
      when :online
        name
      else
        File.basename(path.to_s)
      end
    end

    # What the device page shows as the image's size: upstream leaves it empty
    # for an online image, whose size is not known until it is downloaded.
    def size_string
      case @kind
      when :online
        ""
      else
        SizeFormat.call(File.size(path))
      end
    rescue SystemCallError => e
      warn "Failed to get file metadata: #{e.message}"
      ""
    end

    # The phase a run starts in: an online image downloads first.
    def initial_phase
      case @kind
      when :online
        :download
      else
        :copy
      end
    end
  end
end
