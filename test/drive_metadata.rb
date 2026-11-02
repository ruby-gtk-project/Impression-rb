# frozen_string_literal: true

# Drives the desktop metadata: the desktop entry, the AppStream metainfo and
# the D-Bus service file in data/, the translation merge that both the flake's
# install phase and `rake metadata` run over them, and the file-opening path
# those files hand the app.
#
#   nix develop --command xvfb-run -a ruby test/drive_metadata.rb
#
# GTK is pulled in by the application object, so this wants the dev shell's
# virtual display. The "open" signal is driven by calling the handler the
# application connects rather than by signal_emit: emitting it by hand crashes
# the process, because the signal's C signature carries the file array as a
# pointer plus a count and the bindings have no marshaller for that.

require "fileutils"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "impression"
require "impression/xml"

APP_ID = "io.gitlab.adhami3310.Impression"
DATA = File.expand_path("../data", __dir__)
PO = File.expand_path("../po", __dir__)

FAILURES = []

def check(name)
  result = yield
  puts "ok   #{name} — #{result}"
rescue StandardError, LoadError => e
  FAILURES << name
  puts "FAIL #{name}: #{e.class}: #{e.message}"
  puts e.backtrace.take(4).map { |line| "       #{line}" }
end

def expect(condition, message)
  case condition
  when false, nil
    raise message
  end
end

# The desktop entry and the D-Bus service file are both key-value groups; this
# reads the one group each of them has.
def entries(path)
  File.readlines(path, chomp: true)
    .reject { |line| line.empty? || line.start_with?("#", "[") }
    .to_h { |line| line.split("=", 2) }
end

def desktop = entries(File.join(DATA, "#{APP_ID}.desktop"))

def service = entries(File.join(DATA, "#{APP_ID}.service"))

def metainfo = Impression::Xml.parse(File.read(File.join(DATA, "#{APP_ID}.metainfo.xml")))

check("the desktop entry names the app, its icon and its launcher") do
  keys = desktop
  expect(keys["Name"] == "Impression", "Name is #{keys["Name"].inspect}")
  expect(keys["GenericName"] == "Media Writer", "GenericName is #{keys["GenericName"].inspect}")
  expect(keys["Comment"] == "Create bootable drives", "Comment is #{keys["Comment"].inspect}")
  expect(keys["Type"] == "Application", "Type is #{keys["Type"].inspect}")
  expect(keys["Icon"] == APP_ID, "Icon is #{keys["Icon"].inspect}")
  expect(keys["Exec"] == "impression %u", "Exec is #{keys["Exec"].inspect}")
  [keys["Name"], keys["Icon"], keys["Exec"]].join(" / ")
end

check("the desktop entry's launcher is the one the gem installs") do
  launcher = desktop.fetch("Exec").split.first
  executable = File.expand_path("../exe/#{launcher}", __dir__)
  expect(File.executable?(executable), "#{executable} is not executable")
  launcher
end

check("the desktop entry asks for D-Bus activation and notifications") do
  keys = desktop
  expect(keys["DBusActivatable"] == "true", "DBusActivatable is #{keys["DBusActivatable"].inspect}")
  expect(keys["StartupNotify"] == "true", "StartupNotify is #{keys["StartupNotify"].inspect}")
  expect(
    keys["X-GNOME-UsesNotifications"] == "true",
    "X-GNOME-UsesNotifications is #{keys["X-GNOME-UsesNotifications"].inspect}",
  )
  "DBusActivatable, StartupNotify, X-GNOME-UsesNotifications"
end

check("the desktop entry's categories and keywords are upstream's") do
  keys = desktop
  categories = keys.fetch("Categories").split(";").reject(&:empty?)
  expect(categories.first == "GTK", "categories #{categories.inspect}")
  expect(categories.include?("DiscBurning"), "categories #{categories.inspect}")
  keywords = keys.fetch("Keywords").split(";").reject(&:empty?)
  expect(keywords.first == "usb", "keywords #{keywords.inspect}")
  expect(keywords.length == 12, "#{keywords.length} keywords")
  "#{categories.length} categories, #{keywords.length} keywords"
end

check("every image type the window opens has a MIME type on the entry") do
  types = desktop.fetch("MimeType").split(";").reject(&:empty?)
  expect(types.include?("application/x-iso9660-image"), "types #{types.inspect}")
  expect(types.include?("application/x-raw-disk-image"), "types #{types.inspect}")
  expect(types.include?("application/x-cd-image"), "types #{types.inspect}")
  expect(types.include?("application/x-xz"), "types #{types.inspect}")
  expect(
    Impression::AppWindow::EXTENSIONS.sort == %w[img iso xz],
    "window opens #{Impression::AppWindow::EXTENSIONS.inspect}",
  )
  types.join(", ")
end

check("the metainfo is the app's own component, with no placeholder left in it") do
  component = metainfo
  expect(component.name == "component", "root is #{component.name.inspect}")
  expect(component["type"] == "desktop-application", "type is #{component["type"].inspect}")
  expect(component.child_text("id") == APP_ID, "id is #{component.child_text("id").inspect}")
  expect(
    component.descendant("launchable")["type"] == "desktop-id",
    "launchable type is #{component.descendant("launchable")["type"].inspect}",
  )
  expect(
    component.child_text("launchable") == "#{APP_ID}.desktop",
    "launchable is #{component.child_text("launchable").inspect}",
  )
  expect(
    !File.read(File.join(DATA, "#{APP_ID}.metainfo.xml")).match?(/@[a-z-]+@/),
    "a @placeholder@ survived",
  )
  component.child_text("id")
end

check("the metainfo points at the catalogue domain the app looks up") do
  domain = metainfo.child_text("translation")
  expect(domain == Impression::I18n::DOMAIN, "domain is #{domain.inspect}")
  expect(
    metainfo.descendant("translation")["type"] == "gettext",
    "translation type is #{metainfo.descendant("translation")["type"].inspect}",
  )
  domain
end

check("the metainfo carries the summary, the licences and the release history") do
  component = metainfo
  expect(component.child_text("name") == "Impression", component.child_text("name").inspect)
  expect(
    component.child_text("summary") == "Create bootable drives",
    component.child_text("summary").inspect,
  )
  expect(
    component.child_text("metadata_license") == "CC-BY-SA-4.0",
    component.child_text("metadata_license").inspect,
  )
  expect(
    component.child_text("project_license") == "GPL-3.0",
    component.child_text("project_license").inspect,
  )
  releases = component.child("releases").each_child("release")
  expect(releases.length >= 20, "#{releases.length} releases")
  expect(releases.first["version"] == "3.8.0", "newest is #{releases.first["version"].inspect}")
  "#{releases.length} releases, newest #{releases.first["version"]}"
end

check("the metainfo's screenshots all carry a caption") do
  screenshots = metainfo.descendant("screenshots").each_child("screenshot")
  expect(screenshots.length == 4, "#{screenshots.length} screenshots")
  screenshots.each do |screenshot|
    expect(screenshot.child_text("image").to_s.start_with?("https://"), "image is not a URL")
    expect(!screenshot.child_text("caption").to_s.empty?, "a screenshot has no caption")
  end
  "#{screenshots.length} captioned screenshots"
end

check("the D-Bus service file activates the app in service mode") do
  keys = service
  expect(keys["Name"] == APP_ID, "Name is #{keys["Name"].inspect}")
  command = keys.fetch("Exec").split
  expect(File.basename(command.first) == "impression", "Exec is #{keys["Exec"].inspect}")
  expect(command.first.start_with?("/"), "Exec is not an absolute path: #{keys["Exec"].inspect}")
  expect(command.last == "--gapplication-service", "Exec is #{keys["Exec"].inspect}")
  keys["Exec"]
end

check("the service file's name is the one the app registers on the bus") do
  expect(service.fetch("Name") == Impression::Application::APP_ID, "not the app's own id")
  expect(
    metainfo.child_text("id") == Impression::Application::APP_ID,
    "the metainfo names a different component",
  )
  Impression::Application::APP_ID
end

check("the translations merge into the entry and the metainfo") do
  merged = Dir.mktmpdir("impression-metadata")
  {
    "--desktop" => "#{APP_ID}.desktop",
    "--xml"     => "#{APP_ID}.metainfo.xml",
  }.each do |mode, name|
    system(
      "msgfmt",
      mode,
      "-d",
      PO,
      "--template",
      File.join(DATA, name),
      "-o",
      File.join(merged, name),
      out: File::NULL,
      err: File::NULL,
    ) || raise("msgfmt #{mode} failed; is gettext on PATH?")
  end

  entry = entries(File.join(merged, "#{APP_ID}.desktop"))
  expect(entry["Name[de]"] == "Impression", "Name[de] is #{entry["Name[de]"].inspect}")
  expect(
    entry["Comment[de]"] == "Erstelle bootfähige Laufwerke",
    "Comment[de] is #{entry["Comment[de]"].inspect}",
  )
  expect(entry["Exec"] == "impression %u", "the merge changed Exec to #{entry["Exec"].inspect}")

  component = Impression::Xml.parse(File.read(File.join(merged, "#{APP_ID}.metainfo.xml")))
  german = component.each_child("summary").find { |node| node["xml:lang"] == "de" }
  expect(german, "the metainfo has no German summary")
  expect(german.text == "Erstelle bootfähige Laufwerke", "summary is #{german.text.inspect}")
  FileUtils.remove_entry(merged)
  "#{entry["Comment[de]"]} / #{german.text}"
end

check("the application takes the open flag the desktop entry's %u needs") do
  flags = Impression::Application.new.app.flags
  expect(flags.handles_open?, "flags are #{flags.inspect}")
  flags.inspect
end

check("a launch with a file opens it in the window") do
  opened = []
  image = File.join(Dir.mktmpdir("impression-open"), "linux.iso")
  FileUtils.touch(image)
  Impression::Application.new.tap do |application|
    application.define_singleton_method(:window) do
      @stub ||= Object.new.tap do |stub|
        stub.define_singleton_method(:present) { opened << :present }
        stub.define_singleton_method(:open_path) { |path| opened << path }
      end
    end
    application.build
    application.send(:open, [Gio::File.new_for_path(image)])
  end
  expect(opened == [:present, image], "the window saw #{opened.inspect}")
  FileUtils.remove_entry(File.dirname(image))
  opened.join(" then ")
end

check("a launch with a file that has no local path presents the window only") do
  opened = []
  Impression::Application.new.tap do |application|
    application.define_singleton_method(:window) do
      @stub ||= Object.new.tap do |stub|
        stub.define_singleton_method(:present) { opened << :present }
        stub.define_singleton_method(:open_path) { |path| opened << path }
      end
    end
    application.build
    application.send(:open, [Gio::File.new_for_uri("https://example.com/linux.iso")])
  end
  expect(opened == [:present], "the window saw #{opened.inspect}")
  "presented, nothing opened"
end

puts
case FAILURES.empty?
when true
  puts "all checks passed"
else
  puts "FAILURES: #{FAILURES.join(", ")}"
  exit 1
end
