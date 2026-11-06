# frozen_string_literal: true

require "gtk4"

require_relative "xml"

module Impression
  # Udisks is the bus plumbing the write pipeline (flash_request.rb,
  # windows_installer.rb) uses to drive UDisks2 directly: issuing method
  # calls such as Format, Delete and OpenDevice, and reading properties
  # mid-operation.
  #
  # device_monitor.rb's own device listing goes through the `udisks` gem's
  # typed UDisks::Client instead; this module is the lower-level raw D-Bus
  # plumbing the write pipeline still needs for the method calls the gem's
  # typed proxies also expose, but which have not been ported over yet.
  # Properties go through org.freedesktop.DBus.Properties and object
  # enumeration through org.freedesktop.DBus.Introspectable, because
  # GetManagedObjects' reply type a{oa{sa{sv}}} has no Ruby conversion in
  # plain Gio.
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
end
