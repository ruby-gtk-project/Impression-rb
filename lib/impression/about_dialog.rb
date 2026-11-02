# frozen_string_literal: true

require "adwaita"

require_relative "rb/version"

module Impression
  # AboutDialog is the About window the primary menu opens.
  #
  # Ported from upstream's src/window.rs (show_about). Upstream builds it with
  # from_appdata, reading the metainfo XML out of the GResource bundle; this
  # port has no bundle, so the same fields are set directly.
  class AboutDialog < Adwaita::AboutDialog
    APP_ID = "io.gitlab.adhami3310.Impression"
    WEBSITE = "https://gitlab.com/adhami3310/Impression"

    DEVELOPERS = ["Khaleel Al-Adhami"].freeze
    DESIGNERS = ["Brage Fuglseth https://bragefuglseth.dev"].freeze
    ARTISTS = ["Brage Fuglseth https://bragefuglseth.dev"].freeze
    ACKNOWLEDGEMENTS = ["Popsicle https://github.com/pop-os/popsicle"].freeze

    # Upstream's add_other_app calls: the author's two other apps.
    OTHER_APPS = [
      ["io.gitlab.adhami3310.Footage", "Footage", "Polish your videos"],
      ["io.gitlab.adhami3310.Converter", "Switcheroo", "Convert and manipulate images"],
    ].freeze

    def build
      tap do |dialog|
        dialog.add_acknowledgement_section("Code borrowed from", ACKNOWLEDGEMENTS)
        OTHER_APPS.each { |id, name, summary| dialog.add_other_app(id, name, summary) }
      end
    end

    def initialize
      super()
      self.application_name = "Impression"
      self.application_icon = APP_ID
      self.developer_name = "Khaleel Al-Adhami"
      self.version = Rb::VERSION
      self.comments = "Create bootable drives"
      self.website = WEBSITE
      self.issue_url = "#{WEBSITE}/-/issues"
      self.license_type = Gtk::License::GPL_3_0
      self.developers = DEVELOPERS
      self.designers = DESIGNERS
      self.artists = ARTISTS
      self.translator_credits = "translator-credits"
    end
  end
end
