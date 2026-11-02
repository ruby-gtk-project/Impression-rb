# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "app_window"
require_relative "settings"
require_relative "style"

module Impression
  # Application is the application object: the icons and stylesheet the port
  # loads at startup, the application-wide actions and accelerators, and the
  # one window.
  #
  # Ported from upstream's src/application.rs and src/main.rs, plus the asset
  # loading that src/main.rs does out of the GResource bundle built by
  # data/resources/resources.gresource.xml. A Ruby app has no bundle, so the
  # app's own icons are loaded by adding data/icons to the icon theme's search
  # path and the stylesheet is installed from Style.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APP_ID = "io.gitlab.adhami3310.Impression"

    ICON_PATH = File.expand_path("../../data/icons", __dir__)

    # Upstream's setup_accels.
    ACCELS = {
      "app.quit"              => ["<Control>q"],
      "win.close"             => ["<Control>w"],
      "win.open"              => ["<Control>o"],
      "win.show-help-overlay" => ["<Control>question"],
    }.freeze

    def build
      app.tap do
        app.signal_connect("startup") { startup }
        app.signal_connect("activate") { activate }
      end
    end

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)

    def settings = @settings ||= Settings.new

    def window
      @window ||= AppWindow.new(application: app, settings: settings).tap(&:build)
    end

    private

      def startup
        Gtk::Window.set_default_icon_name(APP_ID)
        icon_theme.add_search_path(ICON_PATH)
        Style.install
        setup_actions
        setup_accels
      end

      # Upstream presents the window it already has, and opens whatever file it
      # was handed; a launch from a shell brings the file along as an argument.
      def activate
        window.present
        ARGV.each { |path| window.open_path(File.expand_path(path)) }
      end

      def icon_theme = Gtk::IconTheme.get_for_display(Gdk::Display.default)

      def setup_actions
        Gio::SimpleAction.new("quit").tap do |action|
          action.signal_connect("activate") { app.quit }
          app.add_action(action)
        end
      end

      def setup_accels
        ACCELS.each { |action, accelerators| app.set_accels_for_action(action, accelerators) }
      end
  end
end
