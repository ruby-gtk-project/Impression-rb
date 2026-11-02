# frozen_string_literal: true

require "gtk4"

require_relative "size_format"
require_relative "xml"

module Impression
  # Udisks is the bus plumbing the device list and the write pipeline share.
  #
  # Upstream reaches UDisks2 through the udisks crate, which wraps the bus and
  # adds client-side helpers. The Ruby bindings have no udisks client, so the
  # calls here are the underlying D-Bus ones made through Gio: properties
  # through org.freedesktop.DBus.Properties, and object enumeration through
  # org.freedesktop.DBus.Introspectable, because GetManagedObjects' reply type
  # a{oa{sa{sv}}} has no Ruby conversion in these bindings.
  module Udisks
    SERVICE = "org.freedesktop.UDisks2"
    MANAGER_PATH = "/org/freedesktop/UDisks2"
    BLOCKS_PATH = "/org/freedesktop/UDisks2/block_devices"

    OBJECT_MANAGER_INTERFACE = "org.freedesktop.DBus.ObjectManager"
    PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"
    INTROSPECTABLE_INTERFACE = "org.freedesktop.DBus.Introspectable"
    BLOCK_INTERFACE = "org.freedesktop.UDisks2.Block"
    DRIVE_INTERFACE = "org.freedesktop.UDisks2.Drive"
    PARTITION_INTERFACE = "org.freedesktop.UDisks2.Partition"
    PARTITION_TABLE_INTERFACE = "org.freedesktop.UDisks2.PartitionTable"
    FILESYSTEM_INTERFACE = "org.freedesktop.UDisks2.Filesystem"

    TIMEOUT = 5000

    # Proxies are per (path, interface) and cheap to keep: a write re-reads the
    # same handful of objects many times over.
    def self.proxy(path, interface)
      proxies[[path, interface]] ||= Gio::DBusProxy.new(
        :system,
        :do_not_load_properties,
        nil,
        SERVICE,
        path,
        interface,
      )
    end

    def self.proxies = @proxies ||= {}

    def self.object_manager = proxy(MANAGER_PATH, OBJECT_MANAGER_INTERFACE)

    # UDisks2 may not be running at all, and a device can vanish between being
    # listed and being asked about; upstream logs and carries on, and so does
    # this.
    def self.call(path, interface, method, parameters = nil)
      proxy(path, interface).call_sync(
        method,
        parameters,
        :none,
        TIMEOUT,
        nil,
      )
    rescue Gio::Error, GLib::Error => e
      warn "UDisks2 #{method} on #{path} failed: #{message_of(e)}"
      nil
    end

    # The same call, but failures are the caller's to handle — the write
    # pipeline has to fail honestly rather than carry on.
    def self.call!(path, interface, method, parameters = nil)
      proxy(path, interface).call_sync(
        method,
        parameters,
        :none,
        TIMEOUT,
        nil,
      )
    end

    def self.message_of(error) = error.message.lines.first.to_s.strip

    # OpenDevice replies with a file descriptor rather than a path, which takes
    # the fd-list form of the call. The reply's handle indexes that list.
    def self.open_device(path, options)
      values, fd_list = proxy(path, BLOCK_INTERFACE).call_with_unix_fd_list_sync(
        "OpenDevice",
        options,
        :none,
        TIMEOUT,
        nil,
        nil,
      )
      fd_list.get(values.first)
    end

    def self.property(path, interface, name)
      call(
        path,
        PROPERTIES_INTERFACE,
        "Get",
        GLib::Variant.parse("('#{interface}', '#{name}')", "(ss)"),
      )&.first
    end

    def self.block_paths
      children_of(BLOCKS_PATH).map { |name| "#{BLOCKS_PATH}/#{name}" }
    end

    def self.interfaces_of(path)
      introspect(path).each_child("interface").filter_map { |node| node["name"] }
    end

    def self.children_of(path)
      introspect(path).each_child("node").filter_map { |node| node["name"] }
    end

    def self.introspect(path)
      reply = call(path, INTROSPECTABLE_INTERFACE, "Introspect")
      Xml.parse(reply.to_a.first.to_s) || Xml::Node.new("node", {})
    end

    # Every partition of a whole-disk block device, which is what udisks'
    # client-side `partitions(&partition_table)` returns.
    def self.partitions_of(path)
      block_paths.select do |candidate|
        property(candidate, PARTITION_INTERFACE, "Table") == path
      end
    end

    # UDisks2 hands byte-array properties over NUL-terminated.
    def self.byte_string(bytes)
      case bytes
      when nil
        nil
      else
        bytes.take_while { |byte| byte.positive? }.pack("C*").force_encoding("UTF-8")
      end
    end
  end

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
  # refresh_devices, device_metadata, device_label): one client, ObjectManager's
  # InterfacesAdded/InterfacesRemoved instead of polling, and a 500 ms debounce
  # so a drive that registers several interfaces in a row triggers one rescan.
  class DeviceMonitor
    CHANGE_SIGNALS = %w[InterfacesAdded InterfacesRemoved].freeze

    DEBOUNCE = 500

    def initialize(&on_devices)
      @on_devices = on_devices
      @pending = nil
    end

    # Hands over the current list, then a new one on every change. Returns self
    # so the caller can keep it alive.
    def start
      tap do
        emit
        Udisks.object_manager.signal_connect("g-signal") do |_proxy, _sender, signal, _parameters|
          case CHANGE_SIGNALS.include?(signal)
          when true
            schedule_refresh
          end
        end
      end
    end

    # Every removable drive's whole-disk block device, sorted by object path the
    # way upstream sorts its drive list.
    def devices
      Udisks.block_paths.filter_map { |path| device_for(path) }.sort_by(&:object_path)
    end

    private

      def emit = @on_devices.call(devices)

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
      def device_for(path)
        drive_path = drive_path_of(path)
        case drive_path
        when nil
          nil
        else
          device_with_drive(path, drive_path)
        end
      end

      def drive_path_of(path)
        interfaces = Udisks.interfaces_of(path)
        whole_disk = interfaces.include?(Udisks::BLOCK_INTERFACE) &&
          !interfaces.include?(Udisks::PARTITION_INTERFACE)
        case whole_disk
        when false
          nil
        else
          drive_of(path)
        end
      end

      def drive_of(path)
        drive_path = Udisks.property(path, Udisks::BLOCK_INTERFACE, "Drive")
        case drive_path
        when nil, "", "/"
          nil
        else
          drive_path
        end
      end

      def device_with_drive(path, drive_path)
        case Udisks.property(drive_path, Udisks::DRIVE_INTERFACE, "Removable")
        when false
          nil
        else
          Device.new(
            object_path:    path,
            display_string: display_string_of(path),
            info:           info_of(path),
            label:          label_of(path, drive_path),
          )
        end
      end

      def display_string_of(path)
        Udisks.byte_string(Udisks.property(path, Udisks::BLOCK_INTERFACE, "PreferredDevice"))
      end

      # Upstream shows udisks' own one-liner for the object. That is a helper of
      # the udisks client library rather than anything on the bus, so the same
      # facts — how big the drive is and which device node it is — are composed
      # from the Block interface here.
      def info_of(path)
        size = Udisks.property(path, Udisks::BLOCK_INTERFACE, "Size")
        node = display_string_of(path)
        case [size, node]
        in [Integer => bytes, String => device]
          "#{SizeFormat.call(bytes)} Drive (#{device})"
        in [Integer => bytes, _]
          "#{SizeFormat.call(bytes)} Drive"
        else
          node
        end
      end

      # Upstream's device_label: the filesystem label, else the first
      # partition's name, each qualified by the drive's hardware description.
      def label_of(path, drive_path)
        hardware = hardware_of(drive_path)
        name = name_of(path)
        case name
        when nil, ""
          hardware
        else
          "#{name} (#{hardware})".strip
        end
      end

      def hardware_of(drive_path)
        [
          Udisks.property(drive_path, Udisks::DRIVE_INTERFACE, "Vendor"),
          Udisks.property(drive_path, Udisks::DRIVE_INTERFACE, "Model"),
        ].compact.join(" ").strip
      end

      def name_of(path)
        label = Udisks.property(path, Udisks::BLOCK_INTERFACE, "IdLabel")
        case label
        when nil, ""
          first_partition_name(path)
        else
          label
        end
      end

      def first_partition_name(path)
        Udisks.partitions_of(path).filter_map do |partition|
          Udisks.property(partition, Udisks::PARTITION_INTERFACE, "Name")
        end.reject(&:empty?).first
      end
  end
end
