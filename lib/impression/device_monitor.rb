# frozen_string_literal: true

require "gio2"
require "udisks"

require_relative "size_format"

module Impression
  # Device is one removable drive's whole-disk block device, with the strings
  # the device list shows for it.
  #
  # Ported from upstream's src/widgets/device_list.rs (DeviceMetadata).
  class Device
    attr_reader :object_path, :display_string, :info, :label

    def initialize(object_path:, display_string:, info:, label:)
      @object_path = object_path
      @display_string = display_string
      @info = info
      @label = label
    end
  end

  # DeviceMonitor watches UDisks2 for removable drives and hands the window a
  # fresh list whenever one appears or disappears.
  #
  # Ported from upstream's src/widgets/device_list.rs (monitor_devices,
  # refresh_devices, device_metadata, device_label): one client, the object
  # manager's object-added/object-removed signals instead of polling, and a
  # 500 ms debounce so a drive that registers several interfaces in a row
  # triggers one rescan.
  #
  # Talks to UDisks2 through the `udisks` gem's generated UDisks::Client — the
  # same client-side helper upstream's udisks crate wraps (get_drive_for_block,
  # get_partitions, get_object_info) — rather than raw
  # org.freedesktop.DBus.Properties/.Introspectable calls through Gio.
  class DeviceMonitor
    DEBOUNCE = 500

    def initialize(&on_devices)
      @on_devices = on_devices
      @client = nil
      @pending = nil
    end

    # Hands over the current list, then a new one on every change. Returns self
    # so the caller can keep it alive.
    def start
      tap do
        connect_client do
          emit
          watch_changes
        end
      end
    end

    # Every removable drive's whole-disk block device, sorted by object path the
    # way upstream sorts its drive list.
    def devices
      case @client
      when nil
        []
      else
        object_manager.objects.filter_map { |object| device_for(object) }.sort_by(&:object_path)
      end
    end

    private

      def emit = @on_devices.call(devices)

      def object_manager = @client.object_manager

      # UDisks2 may not be running at all; upstream logs and gives up quietly,
      # and so does this.
      def connect_client(&block)
        connection = Gio.bus_get_sync(:system, nil)
        UDisks::Client.new_for_connection(connection, nil) do |client, _result, _user_data|
          @client = client
          block.call
        end
      rescue GLib::Error, Gio::Error => e
        warn "Failed to connect to UDisks2: #{message_of(e)}"
      end

      def watch_changes
        object_manager.signal_connect("object-added") { schedule_refresh }
        object_manager.signal_connect("object-removed") { schedule_refresh }
      end

      def message_of(error) = error.message.lines.first.to_s.strip

      # A drive registers several interfaces as it settles; upstream drains the
      # signals for 500 ms and rescans once.
      def schedule_refresh
        case @pending
        when nil
          nil
        else
          GLib::Source.remove(@pending)
        end

        @pending = GLib::Timeout.add(DEBOUNCE) do
          @pending = nil
          emit
          false
        end
      end

      # Upstream keeps a drive unless it is explicitly non-removable, and writes
      # to the drive's whole-disk block device — never to a partition.
      def device_for(object)
        block = object.block
        case [block.nil?, object.partition.nil?]
        in [false, true]
          device_with_drive(object, block)
        else
          nil
        end
      end

      def device_with_drive(object, block)
        drive = @client.get_drive_for_block(block)
        case drive&.removable?
        when nil, false
          nil
        else
          Device.new(
            object_path:    object.object_path,
            display_string: block.preferred_device,
            info:           info_of(object, block),
            label:          label_of(object, block, drive),
          )
        end
      end

      # Upstream shows udisks' own one-liner for the object.
      def info_of(object, block)
        one_liner = @client.get_object_info(object)&.one_liner
        case one_liner
        when nil, ""
          [SizeFormat.call(block.size), "Drive"].join(" ")
        else
          one_liner
        end
      end

      # Upstream's device_label: the filesystem label, else the first
      # partition's name, each qualified by the drive's hardware description.
      def label_of(object, block, drive)
        hardware = hardware_of(drive)
        name = name_of(object, block)
        case name
        when nil, ""
          hardware
        else
          "#{name} (#{hardware})".strip
        end
      end

      def hardware_of(drive)
        [drive.vendor, drive.model].compact.join(" ").strip
      end

      def name_of(object, block)
        label = block.id_label
        case label
        when nil, ""
          first_partition_name(object)
        else
          label
        end
      end

      def first_partition_name(object)
        partition_table = object.partition_table
        case partition_table
        when nil
          nil
        else
          @client.get_partitions(partition_table).filter_map(&:name).reject(&:empty?).first
        end
      end
  end
end
