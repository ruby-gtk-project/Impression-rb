# frozen_string_literal: true

require "gtk4"

module Impression
  # OpenDialog picks the disk image to write.
  #
  # Ported from upstream's src/window.rs (open_dialog), including the filter's
  # mime types and patterns.
  class OpenDialog
    MIME_TYPES = [
      "application/x-iso9660-image",
      "application/x-raw-disk-image",
      "application/x-cd-image",
    ].freeze

    PATTERNS = ["*.iso", "*.img", "*.iso.xz", "*.img.xz", "*.raw.xz"].freeze

    FILTER_NAME = "Disk Images"

    def initialize(&on_file)
      @on_file = on_file
    end

    def present(window)
      dialog.open(window, nil) do |file_dialog, result|
        chosen(file_dialog, result).then do |file|
          case file
          when nil
            nil
          else
            @on_file.call(file)
          end
        end
      end
    end

    def dialog
      @dialog ||= Gtk::FileDialog.new.tap do |file_dialog|
        file_dialog.modal = true
        file_dialog.filters = filters
        file_dialog.default_filter = filter
      end
    end

    private

      # A dismissed dialog reports itself as an error; upstream logs it and
      # leaves the selection alone.
      def chosen(file_dialog, result)
        file_dialog.open_finish(result)
      rescue Gio::Error, GLib::Error => e
        warn "Failed to open file dialog: #{e.message.lines.first.to_s.strip}"
        nil
      end

      def filters
        Gio::ListStore.new(Gtk::FileFilter.gtype).tap do |model|
          model.append(filter)
        end
      end

      def filter
        @filter ||= Gtk::FileFilter.new.tap do |file_filter|
          file_filter.name = FILTER_NAME
          MIME_TYPES.each { |mime_type| file_filter.add_mime_type(mime_type) }
          PATTERNS.each { |pattern| file_filter.add_pattern(pattern) }
        end
      end
  end
end
