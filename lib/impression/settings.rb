# frozen_string_literal: true

require "json"
require "fileutils"

module Impression
  # Settings holds the same keys, defaults and semantics as upstream's
  # GSettings schema.
  #
  # Ported from upstream's data/io.gitlab.adhami3310.Impression.gschema.xml.in.
  #
  # Upstream reads them through gio::Settings, which needs a compiled schema
  # installed into a glib-2.0/schemas directory before the app will even start.
  # Requiring an install step to run the port from a checkout is worse than the
  # alternative, so the keys are backed by a small JSON file under
  # XDG_CONFIG_HOME instead. The schema's own <summary> strings are kept
  # translatable in data/io.gitlab.adhami3310.Impression.gschema.xml.in,
  # which this class otherwise never reads.
  class Settings
    # The schema's downloadable-distros default: (distro_id, must_include,
    # invert_must_include) triples.
    DEFAULT_DISTROS = [
      ["archlinux.org", nil, false],
      ["endlessos.com", nil, false],
      ["fedoraproject.org", "Silverblue", true],
      ["manjaro.org", nil, false],
      ["opensuse.org", nil, false],
      ["ubuntu.com", nil, false],
      ["ubuntu.com", "LTS", false],
    ].freeze

    DEFAULTS = {
      "window-width"         => 500,
      "window-height"        => 600,
      "is-maximized"         => false,
      "downloadable-distros" => DEFAULT_DISTROS,
    }.freeze

    def initialize(path: nil)
      @path = path || default_path
      @values = DEFAULTS.merge(read)
    end

    def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

    def []=(key, value)
      @values[key.to_s] = value
      write
      value
    end

    def location = @path

    DEFAULTS.each_key do |key|
      method_name = key.tr("-", "_")
      define_method(method_name) { self[key] }
      define_method(:"#{method_name}=") { |value| self[key] = value }
    end

    # Upstream's load_window_size.
    def apply_to(window)
      window.set_default_size(self["window-width"], self["window-height"])
      if self["is-maximized"]
        window.maximize
      end
    end

    # Upstream's save_window_size, called from the window's close handler.
    def remember(window)
      @values["is-maximized"] = window.maximized?
      @values["window-width"] = window.default_width
      @values["window-height"] = window.default_height
      write
    end

    private

      def default_path
        File.join(
          ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")),
          "impression-rb",
          "settings.json",
        )
      end

      def read
        case File.exist?(@path)
        when true
          JSON.parse(File.read(@path))
        else
          {}
        end
      rescue JSON::ParserError => e
        warn "Error parsing #{@path}: #{e.message}"
        {}
      end

      def write
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.pretty_generate(@values))
      end
  end
end
