# frozen_string_literal: true

# Drives the translations: compiles one of upstream's catalogues, points the
# app at it, and reads the German strings back off real widgets.
#
#   nix develop --command xvfb-run -a ruby test/drive_i18n.rb
#
# The dev shell carries the de_DE.UTF-8 locale this needs, because gettext
# returns the untranslated string in the C locale however good the catalogue.

require "fileutils"
require "rbconfig"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# glibc maps the locale archive at the first setlocale, which Ruby itself makes
# before this file runs, so LOCALE_ARCHIVE has to be in place before the
# process starts: the drive re-executes itself once with the locale the
# catalogue needs. The dev shell names its own archive in
# IMPRESSION_TEST_LOCALE_ARCHIVE rather than exporting LOCALE_ARCHIVE, which
# would shadow the host's locales for every command in the shell.
case ENV.fetch("IMPRESSION_DRIVE_LOCALE", nil)
when nil
  exec(
    {
      "IMPRESSION_DRIVE_LOCALE" => "de",
      "LOCALE_ARCHIVE"          => ENV.fetch(
        "IMPRESSION_TEST_LOCALE_ARCHIVE",
        ENV.fetch("LOCALE_ARCHIVE", nil),
      ),
      "LANGUAGE"                => "de",
      "LC_ALL"                  => "de_DE.UTF-8",
    }.compact,
    RbConfig.ruby,
    __FILE__,
  )
end

CATALOGUES = Dir.mktmpdir("impression-locale")
ERASED_DE = "Alle Daten auf dem ausgewählten Laufwerk werden gelöscht werden"
PO = File.expand_path("../po", __dir__)

# The catalogue has to be in place before the first lookup binds the domain.
%w[de].each do |language|
  target = File.join(CATALOGUES, language, "LC_MESSAGES")
  FileUtils.mkdir_p(target)
  system(
    "msgfmt",
    "-o",
    File.join(target, "impression.mo"),
    File.join(PO, "#{language}.po"),
    out: File::NULL,
    err: File::NULL,
  ) || raise("msgfmt failed; is gettext on PATH?")
end

ENV["IMPRESSION_LOCALE_DIR"] = CATALOGUES

require "impression"

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

check("the catalogue is found") do
  found = Impression::I18n.locale_dir
  expect(found == CATALOGUES, "found #{found.inspect}")
  found
end

check("a translated string is looked up") do
  written = Impression::I18n.translate("Write")
  expect(written == "Schreiben", "got #{written.inspect}")
  expect(written.encoding == Encoding::UTF_8, "encoding #{written.encoding}")
  written
end

check("a string the catalogue has no entry for passes through") do
  text = Impression::I18n.translate("A string upstream never shipped")
  expect(text == "A string upstream never shipped", "got #{text.inspect}")
  "unchanged"
end

check("the device page's Write button is translated") do
  page = Impression::DevicePage.new(menu_model: nil, on_flash: -> {})
  label = page.flash_button.label
  expect(label == "Schreiben", "got #{label.inspect}")
  expect(
    page.write_group.description == ERASED_DE,
    "group description is #{page.write_group.description.inspect}",
  )
  label
end

check("the status pages are translated") do
  view = Impression::StatusView.new(on_done: -> {}, on_retry: -> {}, on_cancel: -> {})
  expect(view.no_devices_page.title == "Keine Laufwerke", view.no_devices_page.title.inspect)
  expect(view.done_button.label == "Fertigstellen", view.done_button.label.inspect)
  [view.no_devices_page.title, view.done_button.label].join(" / ")
end

check("the phase copy FlashStatus marks is translated where it is shown") do
  view = Impression::StatusView.new(on_done: -> {}, on_retry: -> {}, on_cancel: -> {})
  view.phase = Impression::FlashStatus::PHASES.fetch(:download)
  expect(
    view.flashing_page.title == "Datenträger wird heruntergeladen",
    "got #{view.flashing_page.title.inspect}",
  )
  view.flashing_page.title
end

check("the erase dialog keeps upstream's placeholder") do
  dialog = Impression::EraseDialog.new(device_name: "/dev/sdx") { nil }.dialog
  expect(dialog.heading == "Laufwerk löschen?", "heading #{dialog.heading.inspect}")
  expect(dialog.body.include?("/dev/sdx"), "body #{dialog.body.inspect}")
  "#{dialog.heading} #{dialog.body}"
end

check("the primary menu is translated") do
  menu = Impression::PrimaryMenu.build
  labels = menu.n_items.times.flat_map do |section|
    model = menu.get_item_link(section, "section")
    model.n_items.times.map { |item| model.get_item_attribute_value(item, "label", nil) }
  end
  expect(labels.include?("Tastenkombinationen"), "labels #{labels.inspect}")
  labels.join(", ")
end

FileUtils.remove_entry(CATALOGUES)

puts
case FAILURES.empty?
when true
  puts "all checks passed"
else
  puts "FAILURES: #{FAILURES.join(", ")}"
  exit 1
end
