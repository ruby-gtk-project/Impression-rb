# frozen_string_literal: true

require "gtk4"

require_relative "i18n"

module Impression
  # SaveDialog picks where an online image is downloaded to.
  #
  # Ported from upstream's src/window.rs (save_dialog): the release's own file
  # name is offered, and the chosen path becomes the image's download path.
  class SaveDialog
    include Gettext

    PATTERNS = ["*.img", "*.iso"].freeze

    FILTER_NAME = "Disk Images"

    def initialize(release:, &on_file)
      @release = release
      @on_file = on_file
    end

    def present(window)
      dialog.save(window, nil) do |file_dialog, result|
        chosen(file_dialog, result).then do |file|
          case file&.path
          when nil
            nil
          else
            @on_file.call(file.path)
          end
        end
      end
    end

    def dialog
      @dialog ||= Gtk::FileDialog.new.tap do |file_dialog|
        file_dialog.modal = true
        file_dialog.filters = filters
        file_dialog.default_filter = filter
        file_dialog.initial_name = @release.file_name
      end
    end

    private

      def chosen(file_dialog, result)
        file_dialog.save_finish(result)
      rescue Gio::Error, GLib::Error => e
        warn "Failed to open save dialog: #{e.message.lines.first.to_s.strip}"
        nil
      end

      def filters
        Gio::ListStore.new(Gtk::FileFilter.gtype).tap do |model|
          model.append(filter)
        end
      end

      def filter
        @filter ||= Gtk::FileFilter.new.tap do |file_filter|
          file_filter.name = _(FILTER_NAME)
          PATTERNS.each { |pattern| file_filter.add_pattern(pattern) }
        end
      end
  end
end
