# frozen_string_literal: true

require "gtk4"

module Impression
  # Style is the app stylesheet.
  #
  # Ported from upstream's data/resources/style.css, which is loaded out of the
  # GResource bundle; the port carries the same rules inline and installs them
  # on the display at application priority.
  module Style
    CSS = <<~CSS
      .loading-frame {
        min-height: 200px;
      }

      .architecture button:not(:hover) {
        background: transparent;
      }

      .app_icon {
        -gtk-icon-size: 128px;
        margin-bottom: 24px;
      }

      .drag-overlay-status-page {
        background-color: alpha(var(--accent-bg-color), 0.5);
        color: var(--accent-fg-color);
      }

      .error-message {
        margin: 12px;
      }
    CSS

    # The CSS class upstream's window.rs adds to the window when it was built
    # with `meson -Dprofile=development` (config::PROFILE == "Devel").
    DEVEL_CSS_CLASS = "devel"

    # Upstream bakes PROFILE into src/config.rs.in at meson configure time; the
    # port has no build step, so the same switch is read from the environment
    # at run time instead.
    def self.devel?
      ENV["IMPRESSION_PROFILE"] == "Devel"
    end

    def self.install(display = Gdk::Display.default)
      Gtk::StyleContext.add_provider_for_display(
        display,
        provider,
        Gtk::StyleProvider::PRIORITY_APPLICATION,
      )
    end

    # Upstream's `self.obj().add_css_class("devel")` in window.rs's
    # constructed(), run once the window exists.
    def self.apply_profile(window)
      if devel?
        window.add_css_class(DEVEL_CSS_CLASS)
      end
    end

    def self.provider
      Gtk::CssProvider.new.tap do |css|
        css.load(data: CSS)
      end
    end
  end
end
