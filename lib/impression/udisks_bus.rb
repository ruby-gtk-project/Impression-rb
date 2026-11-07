# frozen_string_literal: true

require "gio2"
require "glib2"
require "udisks"

module Impression
  # Udisks is the typed-gem plumbing the write pipeline (flash_request.rb,
  # windows_installer.rb) uses to drive UDisks2 directly: issuing method
  # calls such as Format, CreatePartitionAndFormat, Unmount, Rescan, Eject
  # and OpenDevice, and reading properties mid-operation.
  #
  # This used to be raw org.freedesktop.DBus.Properties/.Introspectable calls
  # through Gio::DBusProxy, on the theory that GetManagedObjects' reply type
  # a{oa{sa{sv}}} has no Ruby conversion in plain Gio, and that building a
  # UDisks::Client -- an inherently async operation -- is awkward from the
  # write pipeline's own Ruby thread. Neither holds up: the typed client
  # device_monitor.rb already builds (on the main thread, where
  # UDisks::Client.new_for_connection's async callback fires naturally inside
  # the GLib main loop GTK is already running) is the one this module shares
  # -- set once by DeviceMonitor#connect_client -- so the write pipeline's own
  # thread only ever makes plain blocking `call_*_sync` calls against it,
  # which need no main loop of their own to complete, and reads the same
  # object manager cache device_monitor.rb's device list already proves
  # works for enumeration.
  module Udisks
    # Raised by the `!` operations below when no UDisks2 client is connected
    # at all (DeviceMonitor never reached setup_device_monitor's callback) or
    # when path has no block device behind it any more -- distinct from a
    # UDisks2 D-Bus error, which GLib::Error/Gio::Error already cover.
    class Unavailable < StandardError; end

    class << self
      attr_accessor :client
    end

    def self.message_of(error) = error.message.lines.first.to_s.strip

    def self.object_at(path) = client&.object_manager&.get_object(path)

    def self.block_at(path) = object_at(path)&.block

    def self.filesystem_at(path) = object_at(path)&.filesystem

    def self.partition_table_at(path)
      block = block_at(path)
      case block
      when nil
        nil
      else
        client.get_partition_table(block)
      end
    end

    # Every partition of a whole-disk block device, by object path -- what
    # upstream's `partitions(&partition_table)` returns, read off the object
    # manager's own cache instead of walking /block_devices by hand.
    def self.partitions_of(path)
      case client
      when nil
        []
      else
        client.object_manager.objects
          .select { |object| object.partition&.table == path }
          .map(&:object_path)
      end
    end

    # block_at(path), but for the operations below that cannot proceed
    # without one: no silent nil, an explicit failure the write pipeline's
    # own rescue reports like any other.
    def self.block_at!(path)
      block_at(path) || raise(Unavailable, "no UDisks2 block device at #{path}")
    end

    def self.size_of(path) = block_at(path)&.size.to_i

    def self.mounted?(path) = !(filesystem_at(path)&.mount_points || []).empty?

    def self.partition_table?(path) = !partition_table_at(path).nil?

    # UDisks2 may not be running at all, and a device can vanish between being
    # listed and being asked about; upstream logs and carries on, and so does
    # this.
    def self.unmount(path)
      filesystem_at(path)&.call_unmount_sync(force_options, nil)
    rescue GLib::Error, Gio::Error => e
      warn "UDisks2 Unmount on #{path} failed: #{message_of(e)}"
      nil
    end

    def self.rescan(path)
      block_at(path)&.call_rescan_sync(empty_options, nil)
    rescue GLib::Error, Gio::Error => e
      warn "UDisks2 Rescan on #{path} failed: #{message_of(e)}"
      nil
    end

    # Ejects path's drive, if it has one -- upstream ignores a block device
    # with no drive (a loop device, say), exactly as this does.
    def self.eject(path)
      block = block_at(path)
      drive = block.nil? ? nil : client.get_drive_for_block(block)
      drive&.call_eject_sync(empty_options, nil)
    rescue GLib::Error, Gio::Error => e
      warn "UDisks2 Eject on #{path} failed: #{message_of(e)}"
      nil
    end

    # OpenDevice replies with a file descriptor rather than a path, which the
    # typed proxy exposes as a GUnixFDList and the handle indexing it. Failure
    # is the caller's to handle -- the write pipeline has to fail honestly
    # rather than carry on.
    def self.open_device(path)
      handle, fd_list = block_at!(path).call_open_device_sync(
        "rw",
        GLib::Variant.parse("{'flags': <int32 #{File::SYNC}>}", "a{sv}"),
        nil,
        nil,
      )
      fd_list.get(handle)
    end

    # The same call, but failures are the caller's to handle -- the write
    # pipeline has to fail honestly rather than carry on.
    def self.format_gpt!(path)
      block_at!(path).call_format_sync("gpt", empty_options, nil)
    end

    # Wipes path to a GPT disk holding a single vfat partition of size bytes
    # (0 means fill the drive), named volume, and answers the new partition's
    # object path.
    def self.create_partition_and_format!(path, size, volume)
      table = partition_table_at(path) || raise(Unavailable, "no UDisks2 partition table at #{path}")
      result = table.call_create_partition_and_format_sync(
        0,
        size,
        "",
        volume,
        empty_options,
        "vfat",
        GLib::Variant.parse(
          "{'label': <'#{volume}'>, 'update-partition-type': <true>}",
          "a{sv}",
        ),
        nil,
      )
      result.is_a?(Array) ? result.first : result
    end

    def self.empty_options = GLib::Variant.parse("{}", "a{sv}")

    def self.force_options = GLib::Variant.parse("{'force': <true>}", "a{sv}")
  end
end
