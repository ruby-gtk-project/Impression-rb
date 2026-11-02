# frozen_string_literal: true

require "gtk4"

module Impression
  # PrimaryMenu is the hamburger menu both header bars show.
  #
  # Ported from upstream's data/resources/blueprints/window.blp
  # (menu primary_menu).
  module PrimaryMenu
    ITEMS = {
      "Keyboard Shortcuts" => "win.show-help-overlay",
      "About Impression"   => "win.about",
    }.freeze

    def self.build
      Gio::Menu.new.tap do |menu|
        menu.append_section(nil, section)
      end
    end

    def self.section
      Gio::Menu.new.tap do |section|
        ITEMS.each { |label, action| section.append(label, action) }
      end
    end
  end
end
