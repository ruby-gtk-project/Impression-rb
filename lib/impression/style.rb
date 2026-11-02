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

    def self.install(display = Gdk::Display.default)
      Gtk::StyleContext.add_provider_for_display(
        display,
        provider,
        Gtk::StyleProvider::PRIORITY_APPLICATION,
      )
    end

    def self.provider
      Gtk::CssProvider.new.tap do |css|
        css.load(data: CSS)
      end
    end
  end
end
