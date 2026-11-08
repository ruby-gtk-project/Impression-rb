# frozen_string_literal: true

require "adwaita"

require_relative "about_dialog"
require_relative "device_monitor"
require_relative "device_page"
require_relative "device_row"
require_relative "disk_image"
require_relative "erase_dialog"
require_relative "flash_request"
require_relative "flash_status"
require_relative "i18n"
require_relative "notifier"
require_relative "online"
require_relative "open_dialog"
require_relative "primary_menu"
require_relative "save_dialog"
require_relative "settings"
require_relative "shortcuts_dialog"
require_relative "style"
require_relative "status_view"
require_relative "stop_writing_dialog"
require_relative "welcome_page"

module Impression
  # AppWindow is the whole window: the chooser, the device list, and the status
  # pages a write runs on.
  #
  # Ported from upstream's src/window.rs together with the template it binds,
  # data/resources/blueprints/window.blp (template $AppWindow) — the outer
  # Gtk.Stack with its "choose" and "status" pages, the navigation view the
  # chooser pushes through, the window actions, the drop target, the device
  # monitor, the osinfo-db fetch, and the once-a-second poll of the write
  # thread's status.
  class AppWindow
    include Gettext

    TITLE = "Impression"

    CHOOSE = "choose"
    STATUS = "status"

    WELCOME_TAG = "welcome"
    DEVICE_LIST_TAG = "device_list"

    # The extensions upstream accepts before it will look at a file at all.
    EXTENSIONS = %w[iso img xz].freeze

    # Upstream polls the write's shared status once a second, and retries the
    # osinfo-db fetch every ten while the offline screen is up.
    POLL_SECONDS = 1
    RETRY_SECONDS = 10

    attr_reader :application, :settings

    def initialize(application:, settings: Settings.new)
      @application = application
      @settings = settings
      @devices = []
      @selected_device_path = nil
      @selected_image = nil
      @request = nil
    end

    def build
      window.tap do |win|
        win.content = main_stack

        main_stack.tap do |stack|
          stack.add_named(navigation, CHOOSE)
          stack.add_named(status_toolbar, STATUS)

          navigation.tap do |pages|
            pages.add(welcome.build)
            pages.add(device_page.build)
          end

          status_toolbar.tap do |view|
            view.add_top_bar(status_header_bar)
            view.content = toast_overlay

            status_header_bar.pack_end(status_menu_button)
            toast_overlay.child = status_view.build
          end
        end

        win.signal_connect("close-request") { close_requested }

        Style.apply_profile(win)
        setup_actions
        setup_drop_target
        settings.apply_to(win)
        welcome.focus_open_button
        setup_callbacks
      end
    end

    def present = window.present

    # Upstream's open_file: anything without one of the three extensions is
    # refused with a toast rather than written.
    def open_file(file)
      path = file.path
      case path
      when nil
        warn "Failed to get file path for #{file.uri}"
      else
        open_path(path)
      end
    end

    # The same check, for a path handed over on the command line.
    def open_path(path)
      case EXTENSIONS.include?(File.extname(path).delete_prefix("."))
      when false
        toast_overlay.add_toast(Adwaita::Toast.new(_("File is not a Disk Image")))
        warn "Not a Disk Image: #{path}"
      else
        @selected_image = DiskImage.local(path)
        load_stored
      end
    end

    def window
      @window ||= Adwaita::ApplicationWindow.new(application).tap do |win|
        win.title = _(TITLE)
        win.width_request = 360
        win.height_request = 294
      end
    end

    def main_stack
      @main_stack ||= Gtk::Stack.new.tap do |stack|
        stack.transition_type = :crossfade
      end
    end

    def navigation = @navigation ||= Adwaita::NavigationView.new

    def menu_model = @menu_model ||= PrimaryMenu.build

    def welcome
      @welcome ||= WelcomePage.new(
        menu_model: menu_model,
        on_open:    -> { open_dialog.present(window) },
        on_distro:  ->(release) { save_dialog(release) },
      )
    end

    def device_page
      @device_page ||= DevicePage.new(
        menu_model: menu_model,
        on_flash:   -> { flash_dialog },
      )
    end

    def status_view
      @status_view ||= StatusView.new(
        on_done:   -> { done_clicked },
        on_retry:  -> { try_again_clicked },
        on_cancel: -> { cancel_clicked },
      )
    end

    def status_toolbar = @status_toolbar ||= Adwaita::ToolbarView.new

    def status_header_bar = @status_header_bar ||= Adwaita::HeaderBar.new

    def status_menu_button
      @status_menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "open-menu-symbolic"
        button.menu_model = menu_model
        button.tooltip_text = _("Main Menu")
        button.primary = true
      end
    end

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

    def shortcuts_dialog = @shortcuts_dialog ||= ShortcutsDialog.new.build

    def notifier = @notifier ||= Notifier.new(application: application, window: window)

    def device_monitor
      @device_monitor ||= DeviceMonitor.new { |devices| load_devices_into_ui(devices) }
    end

    def open_dialog
      @open_dialog ||= OpenDialog.new { |file| open_file(file) }
    end

    private

      # Upstream's ACTION_ENTRIES on the window.
      def setup_actions
        action("close") { window.close }
        action("about") { AboutDialog.new.build.present(window) }
        action("show-help-overlay") { shortcuts_dialog.present(window) }
        action("open") { open_dialog.present(window) }
      end

      def action(name, &block)
        Gio::SimpleAction.new(name).tap do |simple_action|
          simple_action.signal_connect("activate") { block.call }
          window.add_action(simple_action)
        end
      end

      def setup_drop_target
        Gtk::DropTarget.new(Gdk::FileList.gtype, :copy).tap do |target|
          target.name = "file-drop-target"
          target.signal_connect("drop") { |_target, value, _x, _y| dropped(value) }
          welcome.drag_overlay.drop_target = target
        end
      end

      def dropped(value)
        file = value.files.first
        case file
        when nil
          false
        else
          open_file(file)
          true
        end
      end

      # Upstream's setup_callbacks: start watching for drives, start the
      # offline retry timer, and fetch the distro lists once.
      def setup_callbacks
        device_monitor.start
        GLib::Timeout.add_seconds(RETRY_SECONDS) { retry_distros }
        get_distros
      end

      # Upstream's load_stored: label the device page with the image, then
      # navigate to it.
      def load_stored
        device_page.name = @selected_image.display_name
        device_page.size = @selected_image.size_string
        navigation.push_by_tag(DEVICE_LIST_TAG)
      end

      def save_dialog(release)
        SaveDialog.new(release: release) { |path| chose_download(release, path) }.present(window)
      end

      def chose_download(release, path)
        @selected_image = DiskImage.online(
          url:           release.url,
          download_path: path,
          name:          release.name,
        )
        load_stored
      end

      # Upstream's get_distros. An empty settings list means there is nothing to
      # fetch, and neither the spinner nor the offline screen belongs up.
      def get_distros
        distros = settings["downloadable-distros"]
        case distros.empty?
        when true
          welcome.show_empty
        else
          fetch_distros(distros)
        end
      end

      # Upstream fetches on its tokio runtime and hands the result back to the
      # main context; here the thread is a Ruby one and the hand-back is an
      # idle callback, since every widget call has to happen on the main thread.
      def fetch_distros(distros)
        Thread.new do
          releases = collect_distros(distros)
          GLib::Idle.add do
            apply_distros(releases)
            false
          end
        end
      end

      def collect_distros(distros)
        url = Online.osinfo_db_url
        case url
        when nil
          nil
        else
          Online.collect(url, distros)
        end
      end

      def apply_distros(releases)
        case releases
        in [Array => amd, Array => arm]
          welcome.show_distros(amd, arm)
        else
          welcome.show_offline
        end
      end

      # Upstream's ten-second retry. The page it names belongs to the outer
      # stack, which is what is read here.
      def retry_distros
        retryable = main_stack.visible_child_name == CHOOSE &&
          navigation.visible_page_tag == WELCOME_TAG &&
          welcome.offline?
        case retryable
        when true
          get_distros
        end
        true
      end

      # Upstream's load_devices_into_ui: an unchanged, non-empty list is left
      # alone so the selection survives a spurious signal.
      def load_devices_into_ui(devices)
        unchanged = devices.map(&:object_path) == @devices.map(&:object_path) && !devices.empty?
        case unchanged
        when true
          nil
        else
          refresh_devices(devices)
        end
      end

      def refresh_devices(devices)
        selected = selected_device&.display_string
        @selected_device_path = nil
        @devices = devices

        DeviceRow.load(device_page.available_devices_list, devices, selected) do |path|
          self.selected_device_path = path
        end

        case devices.empty?
        when true
          self.selected_device_path = nil
        end

        navigate_for(devices)
      end

      # A run owns the view: its end-of-run rescan and eject fire a device
      # change, but the flashing, failure and success pages are dismissed by
      # hand, so this must not navigate away from them.
      def navigate_for(devices)
        case status_view.owned_by_run?
        when true
          nil
        else
          show_devices_or_empty(devices)
        end
      end

      def show_devices_or_empty(devices)
        case devices.empty?
        when true
          status_view.show(StatusView::NO_DEVICES)
          main_stack.visible_child_name = STATUS
        else
          main_stack.visible_child_name = CHOOSE
        end
      end

      def selected_device_path=(path)
        device_page.can_write = !path.nil?
        @selected_device_path = path
      end

      def selected_device
        @devices.find { |device| device.object_path == @selected_device_path }
      end

      def running? = @request&.running? == true

      # Upstream's flash_dialog: both a drive and an image have to be chosen
      # before anything is erased.
      def flash_dialog
        case [selected_device, @selected_image]
        in [Device => device, DiskImage => source]
          erase_dialog(device, source).present(window)
        else
          warn "No device or no disk image selected"
        end
      end

      def erase_dialog(device, source)
        EraseDialog.new(device_name: device.display_string.to_s) do
          flash(device, source)
        end
      end

      def flash(device, source)
        main_stack.visible_child_name = STATUS
        status_view.show(StatusView::FLASHING)
        status_view.reset_progress
        status_view.phase = FlashStatus::PHASES.fetch(source.initial_phase)

        @request = FlashRequest.new(source: source, device_path: device.object_path)
        @request.start
        GLib::Timeout.add_seconds(POLL_SECONDS) { advance }
      end

      # Upstream's timeout_add_seconds_local loop: it breaks as soon as the run
      # stops, and otherwise mirrors the shared status onto the page.
      def advance
        case @request&.running?
        when nil, false
          false
        else
          apply_status(@request.status)
        end
      end

      def apply_status(status)
        case status.active?
        when true
          status_view.phase = status.page
          status_view.progress = status.progress
          true
        else
          finish(status)
        end
      end

      def finish(status)
        case status.failed?
        when true
          status_view.show(StatusView::FAILURE)
          status_view.error = status.error
          notifier.notify(_("Failed to write image"))
        else
          status_view.show(StatusView::SUCCESS)
          notifier.notify(_("Image Written"))
        end

        @request.cancel
        @request = nil
        false
      end

      # Upstream's cancel_request.
      def cancel_request(close_after:)
        StopWritingDialog.new { stop_writing(close_after) }.present(window)
      end

      def stop_writing(close_after)
        @request&.cancel
        case close_after
        when true
          window.close
        else
          main_stack.visible_child_name = CHOOSE
        end
      end

      def cancel_clicked
        case running?
        when true
          cancel_request(close_after: false)
        else
          warn "Cancel button clicked while not running"
          main_stack.visible_child_name = CHOOSE
        end
      end

      # Upstream's done_clicked: forget the drives so the next run rescans, and
      # hand focus back to the Open File row.
      def done_clicked
        @devices = []
        main_stack.visible_child_name = STATUS
        status_view.show(StatusView::NO_DEVICES)
        welcome.focus_open_button
      end

      def try_again_clicked
        main_stack.visible_child_name = CHOOSE
      end

      # Upstream's close_request: remember the geometry, and a running write
      # holds the window open until the user confirms stopping it.
      def close_requested
        settings.remember(window)
        case running?
        when true
          cancel_request(close_after: true)
          true
        else
          false
        end
      end
  end
end
