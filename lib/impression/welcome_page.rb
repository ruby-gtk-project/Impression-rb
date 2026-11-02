# frozen_string_literal: true

require "adwaita"

require_relative "distro_row"
require_relative "i18n"
require_relative "drag_overlay"

module Impression
  # WelcomePage is the first page: the app icon, the Open File row, and the
  # direct-download lists.
  #
  # Ported from upstream's data/resources/blueprints/window.blp (the
  # Adw.NavigationPage tagged welcome), with the architecture drop-down
  # handler from src/window.rs (on_architecture_changed).
  class WelcomePage
    include Gettext

    APP_ICON = "io.gitlab.adhami3310.Impression"
    ARCHITECTURES = %w[x86_64 aarch64].freeze

    def initialize(menu_model:, on_open:, on_distro:)
      @menu_model = menu_model
      @on_open = on_open
      @on_distro = on_distro
    end

    def build
      page.tap do
        drag_overlay.build

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = content_box

          header_bar.pack_end(menu_button)

          content_box.tap do |box|
            box.append(preferences_page)

            preferences_page.tap do |prefs|
              prefs.add(intro_group)
              prefs.add(open_group)
              prefs.add(download_group)
            end
          end
        end

        intro_group.tap do |group|
          group.add(app_image)
          group.add(title_label)
        end

        open_group.tap do |group|
          group.add(open_image_button)

          open_image_button.tap do |row|
            row.add_suffix(next_icon)
            row.activatable_widget = next_icon
            row.signal_connect("activated") { @on_open.call }
          end
        end

        download_group.tap do |group|
          group.header_suffix = architecture
          group.add(download_box)

          architecture.signal_connect("notify::selected") do
            architecture_changed
          end

          download_box.tap do |box|
            box.append(download_spinner)
            box.append(offline_screen)
            box.append(distros_box)

            download_spinner.append(spinner)
            offline_screen.append(offline_status)

            distros_box.tap do |lists|
              lists.append(amd_distros)
              lists.append(arm_distros)
            end
          end
        end
      end
    end

    # Upstream's get_distros success path.
    def show_distros(amd_releases, arm_releases)
      load_rows(amd_releases, arm_releases)
      download_spinner.visible = false
      offline_screen.visible = false
      distros_box.visible = true
      architecture.sensitive = true
    end

    # Upstream's get_distros failure path: the ten-second retry timer watches
    # this screen's visibility to know a retry is wanted.
    def show_offline
      download_spinner.visible = false
      offline_screen.visible = true
    end

    # Upstream's path for a settings list with nothing in it: no lists, no
    # spinner, and no offline screen either.
    def show_empty
      load_rows([], [])
      download_spinner.visible = false
      offline_screen.visible = false
    end

    def offline? = offline_screen.visible?

    def focus_open_button = open_image_button.grab_focus

    def page
      @page ||= Adwaita::NavigationPage.new(drag_overlay.bin, _("Impression")).tap do |navigation_page|
        navigation_page.tag = "welcome"
      end
    end

    def drag_overlay
      @drag_overlay ||= DragOverlay.new(title: _("Drop Here to Open"), child: toolbar_view)
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "open-menu-symbolic"
        button.menu_model = @menu_model
        button.tooltip_text = _("Main Menu")
        button.primary = true
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.hexpand = true
        box.vexpand = true
      end
    end

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def intro_group
      @intro_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.margin_bottom = 12
      end
    end

    def app_image
      @app_image ||= Gtk::Image.new.tap do |image|
        image.icon_name = APP_ICON
        image.add_css_class("app_icon")
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new(_("Choose Image")).tap do |label|
        label.add_css_class("title")
        label.add_css_class("title-1")
      end
    end

    def open_group = @open_group ||= Adwaita::PreferencesGroup.new

    def open_image_button
      @open_image_button ||= Adwaita::ActionRow.new.tap do |row|
        row.title = _("Open File…")
      end
    end

    def next_icon
      @next_icon ||= Gtk::Image.new.tap do |image|
        image.icon_name = "go-next-symbolic"
      end
    end

    def download_group
      @download_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Direct Download")
      end
    end

    def architecture
      @architecture ||= Gtk::DropDown.new.tap do |drop_down|
        drop_down.model = Gtk::StringList.new(ARCHITECTURES)
        drop_down.sensitive = false
        drop_down.add_css_class("architecture")
      end
    end

    def download_box = @download_box ||= Gtk::Box.new(:vertical, 0)

    def download_spinner
      @download_spinner ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.add_css_class("card")
        box.add_css_class("loading-frame")
      end
    end

    def spinner
      @spinner ||= Gtk::Spinner.new.tap do |widget|
        widget.valign = :center
        widget.vexpand = true
        widget.height_request = 32
        widget.width_request = 32
        widget.spinning = true
      end
    end

    def offline_screen
      @offline_screen ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.visible = false
        box.add_css_class("card")
      end
    end

    def offline_status
      @offline_status ||= Adwaita::StatusPage.new.tap do |page|
        page.title = _("No Connection")
        page.description = _("Connect to the internet to view available images")
        page.add_css_class("dim-label")
      end
    end

    def distros_box
      @distros_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.visible = false
      end
    end

    def amd_distros
      @amd_distros ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("boxed-list")
      end
    end

    def arm_distros
      @arm_distros ||= Gtk::ListBox.new.tap do |list|
        list.visible = false
        list.selection_mode = :none
        list.add_css_class("boxed-list")
      end
    end

    private

      def load_rows(amd_releases, arm_releases)
        DistroRow.load(amd_distros, amd_releases) { |release| @on_distro.call(release) }
        DistroRow.load(arm_distros, arm_releases) { |release| @on_distro.call(release) }
      end

      # Upstream's on_architecture_changed: index 0 is x86_64, index 1 aarch64.
      def architecture_changed
        case architecture.selected
        when 0
          amd_distros.visible = true
          arm_distros.visible = false
        when 1
          amd_distros.visible = false
          arm_distros.visible = true
        end
      end
  end
end
