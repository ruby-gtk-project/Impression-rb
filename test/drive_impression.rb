# frozen_string_literal: true

# Drives the whole app headlessly: opens the window, opens and dismisses
# every dialog, walks the welcome page's download states, opens a disk image
# both the valid and the refused way, loads fake drives into the device list,
# fires the flash action through to a real (and, with no real hardware,
# necessarily failing) write, and screenshots each state.
#
#   nix develop --command xvfb-run -a ruby test/drive_impression.rb
#
# The backend drivers (drive_metadata.rb, drive_windows_installer.rb,
# drive_i18n.rb) cover the non-widget half: this file is what needs a window.

require "fileutils"
require "tmpdir"

# A scratch config and cache directory, so a run never reads or writes the
# real ones.
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("impression-drive-config")
ENV["XDG_CACHE_HOME"]  = Dir.mktmpdir("impression-drive-cache")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "impression"
require_relative "gtk_driver"

SHOTS = File.expand_path("../tmp/shots", __dir__)
FileUtils.rm_rf(SHOTS)

# This machine has no network reachable from the sandbox, and the osinfo-db
# fetch is not what this file is testing — the welcome page's three download
# states (loading, offline, populated) are. Pin the lookup so the offline path
# is deterministic instead of depending on whatever DNS happens to resolve.
module Impression
  module Online
    def self.osinfo_db_url = nil
  end
end

# The sandbox this runs in does have a real system D-Bus, and sometimes a
# real (if driveless) UDisks2 on it. A real DeviceMonitor tick racing the
# driver's own fake refresh_devices calls would make every later step
# nondeterministic — whichever one lands last wins the device list. The
# device list itself is this file's job to drive by hand, so the real
# monitor is stubbed out rather than left to collide with it.
module Impression
  class DeviceMonitor
    def start = self
  end
end

# A disk image big enough that SizeFormat has something to show, named so the
# window's extension check accepts it. Not an ISO9660 image, and not named
# .iso, so the Windows-installer path's `iso?` check skips it and the write
# pipeline falls straight to the raw copy — which is the path a fake,
# non-existent block device can actually exercise.
IMAGE_DIR = Dir.mktmpdir("impression-drive-image")
GOOD_IMAGE = File.join(IMAGE_DIR, "disk.img")
File.write(GOOD_IMAGE, "x" * 4096)

BAD_EXTENSION_FILE = File.join(IMAGE_DIR, "notes.txt")
File.write(BAD_EXTENSION_FILE, "not a disk image")

# A widget changed on this tick has not necessarily been laid out and
# painted by the time the step's block returns — the render node comes back
# nil until a frame actually happens. Draining the context a few times before
# a screenshot gives GTK the frames it needs without sleeping the process (a
# driver step may not block the main loop it is itself waiting on).
def settle(times = 20)
  times.times { GLib::MainContext.default.iteration(false) }
end

# Binding quirk found while writing this file: emitting an AlertDialog's
# "response" signal by hand runs the app's own handler (the thing under
# test), but — unlike a real button click — does not also close the dialog;
# that close is libadwaita's own response handling and signal_emit does not
# reach it. Worse, a dialog still open blocks the window it sits over from
# closing at all (win.close silently no-ops while a dialog is attached), so
# a handler that itself calls window.close — StopWritingDialog's does — has
# to see the dialog already gone. Every simulated response below therefore
# closes the dialog *before* emitting the signal, which both matches what a
# real click does (the dialog closes, then the response fires) and avoids
# the stacked-dialogs trap the testing skill warns about.

FakeFile = Struct.new(:path, :uri)

# flash_dialog pattern-matches the selected device against Impression::Device
# itself, so the stand-in for a drive has to be one, not just something
# shaped like one.
FakeDevice = Impression::Device

GtkDriver.drive(Impression::Application.new, shots: SHOTS, timeout: 60) do |d, app|
  d.window { app.window.window }

  d.step("build the window") do
    d.check("main stack opens on the chooser") { app.window.send(:main_stack).visible_child_name == "choose" }
    d.check("navigation opens on the welcome page") { app.window.navigation.visible_page_tag == "welcome" }
    d.check("the open-file row has focus") { app.window.welcome.open_image_button.has_focus? }
    settle
    d.shot("01-welcome")
  end

  d.step("welcome page: empty downloadable-distros list") do
    app.window.welcome.show_empty
    d.check("spinner hidden") { !app.window.welcome.download_spinner.visible? }
    d.check("offline screen hidden") { !app.window.welcome.offline_screen.visible? }
    d.check("amd distro list empty") { app.window.welcome.amd_distros.observe_children.n_items.zero? }
    d.check("arm distro list empty") { app.window.welcome.arm_distros.observe_children.n_items.zero? }
    settle
    d.shot("02-welcome-empty")
  end

  d.step("welcome page: offline") do
    app.window.welcome.show_offline
    d.check("offline screen visible") { app.window.welcome.offline? }
    d.check("spinner hidden") { !app.window.welcome.download_spinner.visible? }
    settle
    d.shot("03-welcome-offline")
  end

  d.step("welcome page: populated with distros, architecture toggle") do
    amd = [Impression::DistroRelease.new(name: "Fedora", version: "41", url: "https://example.test/fedora-41-x86_64.iso")]
    arm = [Impression::DistroRelease.new(name: "Fedora", version: "41", url: "https://example.test/fedora-41-aarch64.iso")]
    app.window.welcome.show_distros(amd, arm)

    d.check("offline screen hidden again") { !app.window.welcome.offline? }
    d.check("distros box visible") { app.window.welcome.distros_box.visible? }
    d.check("architecture dropdown enabled") { app.window.welcome.architecture.sensitive? }
    d.check("amd row loaded") { app.window.welcome.amd_distros.observe_children.n_items == 1 }
    d.check("arm row loaded") { app.window.welcome.arm_distros.observe_children.n_items == 1 }
    d.check("amd list showing by default (index 0)") { app.window.welcome.amd_distros.visible? && !app.window.welcome.arm_distros.visible? }

    app.window.welcome.architecture.selected = 1
  end

  d.step("welcome page: switched to aarch64") do
    d.check("arm list showing, amd hidden") { app.window.welcome.arm_distros.visible? && !app.window.welcome.amd_distros.visible? }
    app.window.welcome.architecture.selected = 0
    settle
    d.shot("04-welcome-distros")
  end

  d.step("shortcuts dialog opens and closes") do
    app.window.shortcuts_dialog.present(app.window.window)
  end

  d.step("shortcuts dialog is the visible dialog") do
    dialog = app.window.window.visible_dialog
    d.check("shortcuts dialog is showing") { !dialog.nil? }
    settle
    d.shot("05-shortcuts")
    dialog&.close
  end

  d.step("about dialog opens and closes") do
    @about = Impression::AboutDialog.new.build
    @about.present(app.window.window)
  end

  d.step("about dialog is the visible dialog") do
    dialog = app.window.window.visible_dialog
    d.check("about dialog is showing") { !dialog.nil? && dialog.equal?(@about) }
    d.check("about dialog carries the app name") { dialog.application_name == "Impression" }
    settle
    d.shot("06-about")
    dialog&.close
  end

  d.step("refuse a file with the wrong extension") do
    before = app.window.instance_variable_get(:@selected_image)
    app.window.open_file(FakeFile.new(BAD_EXTENSION_FILE, "file://#{BAD_EXTENSION_FILE}"))
    d.check("selection unchanged") { app.window.instance_variable_get(:@selected_image).equal?(before) }
    d.check("still on the welcome page") { app.window.navigation.visible_page_tag == "welcome" }
  end

  d.step("open a valid disk image") do
    app.window.open_file(FakeFile.new(GOOD_IMAGE, "file://#{GOOD_IMAGE}"))
    d.check("navigated to the device page") { app.window.navigation.visible_page_tag == "device_list" }
    d.check("device page shows the image name") { app.window.device_page.name == "disk.img" }
    d.check("device page shows a size") { !app.window.device_page.size_label.label.to_s.empty? }
    d.check("write button disabled, no drive yet") { !app.window.device_page.flash_button.sensitive? }
    settle
    d.shot("07-device-page-no-drives")
  end

  d.step("load one fake drive") do
    device = FakeDevice.new(
      object_path:    "/org/freedesktop/UDisks2/block_devices/impression_test_fake",
      display_string: "/dev/impression-test-fake",
      info:           "4.0 GB Drive",
      label:          "TESTDRIVE (Fake Vendor Model)",
    )
    app.window.send(:refresh_devices, [device])
    d.check("one row in the device list") { app.window.device_page.available_devices_list.observe_children.n_items == 1 }
    d.check("the lone drive is preselected") { app.window.instance_variable_get(:@selected_device_path) == device.object_path }
    d.check("write button enabled now a drive and an image are chosen") { app.window.device_page.flash_button.sensitive? }
    settle
    d.shot("08-device-page-one-drive")
  end

  d.step("empty device list shows the no-drives state") do
    app.window.send(:refresh_devices, [])
    d.check("status page is showing") { app.window.send(:main_stack).visible_child_name == "status" }
    d.check("status view on the no-drives page") { app.window.status_view.visible == "no_devices" }
    settle
    d.shot("09-no-drives-status")

    # Put a drive back so the flash flow below has something to erase.
    @device = FakeDevice.new(
      object_path:    "/org/freedesktop/UDisks2/block_devices/impression_test_fake",
      display_string: "/dev/impression-test-fake",
      info:           "4.0 GB Drive",
      label:          "TESTDRIVE (Fake Vendor Model)",
    )
    app.window.send(:refresh_devices, [@device])
    app.window.send(:main_stack).visible_child_name = "choose"
  end

  d.step("flash action opens the erase confirmation") do
    app.window.send(:flash_dialog)
  end

  d.step("erase dialog names the drive, cancel leaves nothing started") do
    dialog = app.window.window.visible_dialog
    d.check("erase dialog is showing") { !dialog.nil? }
    d.check("erase dialog names the drive") { dialog.body.to_s.include?(@device.display_string) }
    settle
    d.shot("10-erase-dialog")
    dialog.close
    dialog.signal_emit("response", "cancel")
    d.check("cancelling starts no write") { !app.window.send(:running?) }
  end

  d.step("flash action again, this time confirmed") do
    app.window.send(:flash_dialog)
  end

  d.step("confirming erase starts the write") do
    dialog = app.window.window.visible_dialog
    dialog.close
    dialog.signal_emit("response", "erase")
    d.check("status page is showing") { app.window.send(:main_stack).visible_child_name == "status" }
    d.check("flashing page is showing") { app.window.status_view.visible == "flashing" }
    d.check("a request is running") { app.window.send(:running?) }
    settle
    d.shot("11-flashing")
  end

  # The fake device has no real block device behind it, so the copy step
  # cannot succeed; this is the only honest way to reach the failure page
  # without real hardware. The window polls the write thread once a second
  # (AppWindow::POLL_SECONDS), so give it real wall-clock time rather than
  # just another driver tick.
  d.step("wait for the write to fail against the fake device") do
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until !app.window.send(:running?) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep(0.2)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    end
  end

  d.step("the failure page is showing with an error message") do
    d.check("request finished") { !app.window.send(:running?) }
    d.check("status page is showing") { app.window.send(:main_stack).visible_child_name == "status" }
    d.check("failure page is showing") { app.window.status_view.visible == "failure" }
    d.check("an error message is present") { !app.window.status_view.send(:error_message_label).label.to_s.empty? }
    settle
    d.shot("12-failure")
  end

  d.step("retry returns to the chooser") do
    app.window.status_view.send(:try_again_button).signal_emit("clicked")
    d.check("back on the chooser stack page") { app.window.send(:main_stack).visible_child_name == "choose" }
    settle
    d.shot("13-retry")
  end

  d.step("stop-writing dialog guards a running write on window close") do
    # Start a second run so there is something running to guard.
    app.window.send(:flash_dialog)
    dialog = app.window.window.visible_dialog
    dialog&.close
    dialog&.signal_emit("response", "erase")
    d.check("a request is running") { app.window.send(:running?) }
  end

  d.step("close-request while running raises the stop-writing dialog") do
    guarded = app.window.send(:close_requested)
    d.check("close was intercepted") { guarded == true }
    dialog = app.window.window.visible_dialog
    d.check("stop-writing dialog is showing") { !dialog.nil? }
    settle
    d.shot("14-stop-writing")
    dialog.close
    dialog.signal_emit("response", "stop")
  end

  # close_requested raised this dialog with close_after: true (a close was in
  # flight when the write was still running), so stop_writing's true branch
  # closes the window rather than returning to the chooser — the same branch
  # a plain Cancel click never takes, since that one is always close_after:
  # false.
  #
  # There is deliberately no further step after this one: closing the
  # window closes this app's only window, which ends the Gtk::Application
  # and the very run loop this driver's steps are scheduled on, so a step
  # placed after this one would simply never be reached. The driver exiting
  # cleanly here with every check above passed, instead of hanging until the
  # watchdog timeout, is itself the proof that the close really happened —
  # the same thing an earlier, narrower version of this script checked
  # directly by reading window.visible? after the fact, before discovering
  # that there is no "after" to read it in.
end
