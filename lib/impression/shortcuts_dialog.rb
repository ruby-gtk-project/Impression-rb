# frozen_string_literal: true

require "adwaita"

module Impression
  # ShortcutsDialog lists the keyboard shortcuts.
  #
  # Ported from upstream's data/resources/blueprints/window.blp
  # (Adw.ShortcutsDialog help_overlay), whose single "General" section names
  # the three window and application actions. Upstream's items carry action
  # names and let libadwaita look the accelerator up; the items here carry the
  # accelerators this port binds, which is the form the Ruby bindings'
  # constructor takes.
  class ShortcutsDialog < Adwaita::ShortcutsDialog
    SECTIONS = {
      "General" => [
        ["Open File", "<Control>o"],
        ["Show Shortcuts", "<Control>question"],
        ["Quit", "<Control>q"],
      ],
    }.freeze

    def initialize
      super()
      self.title = "Keyboard Shortcuts"
    end

    def build
      tap do |dialog|
        SECTIONS.each do |title, items|
          dialog.add(section(title, items))
        end
      end
    end

    private

      def section(title, items)
        Adwaita::ShortcutsSection.new.tap do |section|
          section.title = title
          items.each { |label, accelerator| section.add(item(label, accelerator)) }
        end
      end

      # Positional, not keyword, arguments — even though the error a no-argument
      # new raises advertises the signature as "title:, accelerator:".
      def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
  end
end
