# frozen_string_literal: true

require "adwaita"

module Impression
  # DevicePage is the second page: what is being written, which drive it goes
  # to, and the button that starts the write.
  #
  # Ported from upstream's data/resources/blueprints/window.blp (the
  # Adw.NavigationPage tagged device_list).
  class DevicePage
    def initialize(menu_model:, on_flash:)
      @menu_model = menu_model
      @on_flash = on_flash
    end

    def build
      page.tap do
        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = preferences_page

          header_bar.pack_end(menu_button)

          preferences_page.tap do |prefs|
            prefs.add(image_group)
            prefs.add(devices_group)
            prefs.add(write_group)
          end
        end

        image_group.tap do |group|
          group.add(image_box)

          image_box.tap do |box|
            box.append(disk_image)
            box.append(name_value_label)
            box.append(size_label)
          end
        end

        devices_group.tap do |group|
          group.add(devices_clamp)

          devices_clamp.child = available_devices_list
        end

        write_group.tap do |group|
          group.add(flash_button)

          flash_button.signal_connect("clicked") { @on_flash.call }
        end
      end
    end

    def name = name_value_label.label

    def name=(text)
      name_value_label.label = text.to_s
    end

    def size=(text)
      size_label.label = text.to_s
    end

    def can_write=(writable)
      flash_button.sensitive = writable
    end

    def page
      @page ||= Adwaita::NavigationPage.new(toolbar_view, "Impression").tap do |navigation_page|
        navigation_page.tag = "device_list"
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "open-menu-symbolic"
        button.menu_model = @menu_model
        button.tooltip_text = "Main Menu"
        button.primary = true
      end
    end

    def preferences_page
      @preferences_page ||= Adwaita::PreferencesPage.new.tap do |prefs|
        prefs.valign = :center
      end
    end

    def image_group = @image_group ||= Adwaita::PreferencesGroup.new

    def image_box = @image_box ||= Gtk::Box.new(:vertical, 12)

    def disk_image
      @disk_image ||= Gtk::Image.new.tap do |image|
        image.icon_name = "media-optical-cd-symbolic"
        image.pixel_size = 64
        image.add_css_class("dim-label")
      end
    end

    def name_value_label
      @name_value_label ||= Gtk::Label.new.tap do |label|
        label.wrap = true
        label.wrap_mode = :word_char
        label.lines = 3
        label.justify = :center
        label.max_width_chars = 24
        label.add_css_class("title-3")
      end
    end

    def size_label
      @size_label ||= Gtk::Label.new.tap do |label|
        label.justify = :center
        label.add_css_class("caption")
      end
    end

    def devices_group = @devices_group ||= Adwaita::PreferencesGroup.new

    def devices_clamp
      @devices_clamp ||= Adwaita::Clamp.new.tap do |clamp|
        clamp.maximum_size = 450
        clamp.tightening_threshold = 200
      end
    end

    def available_devices_list
      @available_devices_list ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("boxed-list")
      end
    end

    def write_group
      @write_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.valign = :end
        group.halign = :center
        group.description = "All data on the selected drive will be erased"
      end
    end

    def flash_button
      @flash_button ||= Gtk::Button.new.tap do |button|
        button.label = "Write"
        button.sensitive = false
        button.halign = :center
        button.add_css_class("destructive-action")
        button.add_css_class("pill")
      end
    end
  end
end
