# frozen_string_literal: true

require "adwaita"

module Impression
  # DistroRow is one downloadable image in the welcome page's lists.
  #
  # Ported from upstream's src/window.rs (load_distros), which clears the list
  # box and appends an activatable ActionRow per release, each opening the save
  # dialog for that release.
  class DistroRow
    # Replaces a list box's rows with one per release.
    def self.load(list_box, releases, &on_activate)
      list_box.remove_all
      releases.each do |release|
        list_box.append(new(release: release, &on_activate).build)
      end
    end

    def initialize(release:, &on_activate)
      @release = release
      @on_activate = on_activate
    end

    def build
      row.tap do |action_row|
        action_row.add_suffix(next_image)
        action_row.activatable_widget = next_image

        action_row.signal_connect("activated") do
          @on_activate.call(@release)
        end
      end
    end

    def row
      @row ||= Adwaita::ActionRow.new.tap do |action_row|
        action_row.title = @release.name
        action_row.subtitle = @release.version.to_s
      end
    end

    def next_image
      @next_image ||= Gtk::Image.new.tap do |image|
        image.icon_name = "go-next-symbolic"
      end
    end
  end
end
