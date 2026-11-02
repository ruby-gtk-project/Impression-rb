# frozen_string_literal: true

require "adwaita"

module Impression
  # DeviceRow is one drive in the device page's list, with the radio button
  # that selects it.
  #
  # Ported from upstream's src/widgets/device_list.rs (fn new): every check
  # button joins the first one's group, the drive matching the previous
  # selection (or the first drive when there was none) starts selected, and a
  # lone drive cannot be deselected.
  class DeviceRow
    # Replaces a list box's rows with one per device, selecting the device whose
    # display string matches `selected`, or the first one.
    def self.load(list_box, devices, selected, &on_select)
      list_box.remove_all
      rows(devices, &on_select).tap do |built|
        built.each { |row| list_box.append(row.build) }
        preselect(built, devices, selected)
      end
    end

    def self.rows(devices, &on_select)
      [].tap do |built|
        devices.each do |device|
          built << new(device: device, group: built.first&.check_button, only: devices.one?, &on_select)
        end
      end
    end

    # Upstream activates the matching device, and falls back to the first one
    # when nothing was selected before.
    def self.preselect(built, devices, selected)
      matching = built.find { |row| row.device.display_string == selected }
      case [matching, selected]
      in [DeviceRow => row, _]
        row.select!
      in [nil, nil]
        built.first&.select!
      else
        nil
      end
    end

    attr_reader :device

    def initialize(device:, group:, only:, &on_select)
      @device = device
      @group = group
      @only = only
      @on_select = on_select
    end

    def build
      row.tap do |action_row|
        action_row.add_prefix(check_button)
        action_row.activatable_widget = check_button

        check_button.signal_connect("toggled") do |button|
          toggled(button)
        end
      end
    end

    def select! = check_button.active = true

    def row
      @row ||= Adwaita::ActionRow.new.tap do |action_row|
        action_row.title = device.label.to_s
        action_row.subtitle = device.info.to_s
      end
    end

    def check_button
      @check_button ||= Gtk::CheckButton.new.tap do |button|
        button.valign = :center
        button.add_css_class("selection_mode")
        case @group
        when nil
          nil
        else
          button.group = @group
        end
      end
    end

    private

      # A single drive is always the selection: upstream re-activates the button
      # rather than letting the user end up with nothing selected.
      def toggled(button)
        case @only
        when true
          button.active = true
          @on_select.call(device.object_path)
        else
          select_when_active(button)
        end
      end

      def select_when_active(button)
        case button.active?
        when true
          @on_select.call(device.object_path)
        end
      end
  end
end
