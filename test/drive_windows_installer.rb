# frozen_string_literal: true

# Drives the Windows installer backend against real media rather than mocks:
# a UDF ISO built with genisoimage (which is what libudf reads), a WIM built
# with wimlib-imagex (which is what libwim splits), and the FAT32 image the
# installer stages with mkfs.vfat and mcopy.
#
# Everything here runs without a USB device and without root; GTK is pulled in
# by the udisks plumbing, so it wants the dev shell's virtual display:
#
#   nix develop --command xvfb-run -a ruby test/drive_windows_installer.rb
#
# The two steps a USB stick is needed for — udisks partitioning the drive and
# cloning the staged image onto it — are the only ones left out.

require "digest"
require "fileutils"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "impression/udf"
require "impression/wim"
require "impression/windows_installer"

FAILURES = []

# install.wim + bootx64.efi + setup.exe + ReallyLongInstallerName.xml
TOTAL_BYTES = (3 * 1024 * 1024) + 4096 + 1024 + 4

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

def sh(command)
  expect(
    system(*command, out: File::NULL, err: File::NULL),
    "command failed: #{command.join(" ")}",
  )
end

# genisoimage, not xorrisofs: xorriso cannot write a UDF filesystem, and UDF is
# what a Windows installer ISO carries.
def write_iso(label, output, tree, udf: true)
  sh(%w[genisoimage] + udf_flag(udf) + ["-V", label, "-quiet", "-o", output, tree])
end

def udf_flag(udf)
  case udf
  when true
    %w[-udf]
  else
    []
  end
end

def mtools(command)
  `MTOOLS_SKIP_CHECK=1 #{command}`
end

ROOT = Dir.mktmpdir("impression-drive")
TREE = File.join(ROOT, "tree")
FileUtils.mkdir_p(File.join(TREE, "sources"))
FileUtils.mkdir_p(File.join(TREE, "efi", "boot"))
File.binwrite(File.join(TREE, "sources", "install.wim"), "W" * (3 * 1024 * 1024))
File.binwrite(File.join(TREE, "sources", "ReallyLongInstallerName.xml"), "<x/>")
File.binwrite(File.join(TREE, "efi/boot", "bootx64.efi"), "E" * 4096)
File.binwrite(File.join(TREE, "setup.exe"), "S" * 1024)
ISO = File.join(ROOT, "win.iso")
write_iso("WIN11_TEST", ISO, TREE)

image = nil

check("Udf::Image.open on the UDF ISO") do
  image = Impression::Udf::Image.open(ISO)
  "opened"
end

check("volume_label reads the ISO label") do
  label = image.volume_label
  expect(label == "WIN11_TEST", "got #{label.inspect}")
  label
end

check("path? finds sources/install.wim and misses what is absent") do
  expect(image.path?("sources/install.wim"), "missing install.wim")
  expect(!image.path?("sources/install.esd"), "found a ghost")
  "both answers correct"
end

check("entries lists the whole tree, long names included") do
  entries = image.entries
  paths = entries.map(&:path).sort
  %w[
    sources
    sources/install.wim
    sources/ReallyLongInstallerName.xml
    efi
    efi/boot
    efi/boot/bootx64.efi
    setup.exe
  ].each do |want|
    expect(paths.include?(want), "#{want} not in #{paths.inspect}")
  end
  wim = entries.find { |entry| entry.path == "sources/install.wim" }
  expect(wim.length == 3 * 1024 * 1024, "wim length #{wim.length}")
  expect(entries.find { |entry| entry.path == "sources" }.directory?, "sources not a directory")
  "#{entries.count} entries"
end

check("extract_all reproduces the tree byte for byte") do
  dest = File.join(ROOT, "extracted")
  FileUtils.mkdir_p(dest)
  seen = []
  image.extract_all(
    dest,
    on_progress: ->(done, total) { seen << [done, total] },
    cancelled:   -> { false },
  )
  %w[sources/install.wim efi/boot/bootx64.efi setup.exe].each do |relative|
    want = Digest::SHA256.file(File.join(TREE, relative)).hexdigest
    got = Digest::SHA256.file(File.join(dest, relative)).hexdigest
    expect(want == got, "#{relative} differs")
  end
  expect(!seen.empty?, "no progress reported")
  expect(seen.last.last == TOTAL_BYTES, "progress total wrong: #{seen.last.inspect}")
  "#{seen.count} progress reports, last #{seen.last.inspect}"
end

check("extract_all honours cancellation") do
  dest = File.join(ROOT, "cancelled")
  FileUtils.mkdir_p(dest)
  begin
    image.extract_all(dest, cancelled: -> { true })
    raise "expected Cancelled"
  rescue Impression::Udf::Cancelled
    "cancelled"
  end
end

check("Image#close") do
  image.close
  "closed"
end

WIM_SOURCE = File.join(ROOT, "wimtree")
FileUtils.mkdir_p(WIM_SOURCE)
File.binwrite(File.join(WIM_SOURCE, "payload.bin"), "P" * (1024 * 1024))
WIM_FILE = File.join(ROOT, "install.wim")
sh(["wimlib-imagex", "capture", WIM_SOURCE, WIM_FILE, "test", "--compress=none"])

check("Wim.split writes the .swm part") do
  output = File.join(ROOT, "install.swm")
  Impression::Wim.split(WIM_FILE, output) { true }
  expect(File.file?(output), "no install.swm")
  "#{File.size(output)} bytes"
end

check("Wim.split aborts through the progress callback") do
  begin
    Impression::Wim.split(WIM_FILE, File.join(ROOT, "cancelled.swm")) { false }
    raise "expected Cancelled"
  rescue Impression::Wim::Cancelled
    "cancelled"
  end
end

check("Wim.split reports a bad input") do
  plain = File.join(ROOT, "plain.txt")
  File.binwrite(plain, "not a wim")
  begin
    Impression::Wim.split(plain, File.join(ROOT, "bad.swm")) { true }
    raise "expected Failed"
  rescue Impression::Wim::Failed => e
    e.message
  end
end

# A stand-in for FlashRequest: the installer asks it for the cache directory,
# for whether the write is still wanted, and for somewhere to publish status.
class StubRequest
  attr_reader :published, :cache_dir

  def initialize(cache_dir)
    @cache_dir = cache_dir
    @published = []
  end

  def device_path = "/org/freedesktop/UDisks2/block_devices/nonexistent"

  def running? = true

  def check_running = nil

  def publish(status) = @published << status

  def copy_to_device(_source, _target) = raise("the drive stops before the device write")
end

REQUEST = StubRequest.new(File.join(ROOT, "cache"))
INSTALLER = Impression::WindowsInstaller.new(request: REQUEST, source_path: ISO)
WORK_DIR = File.join(REQUEST.cache_dir, "impression-windows")

check("iso? recognises the source") do
  expect(INSTALLER.send(:iso?), "iso not recognised")
  other = Impression::WindowsInstaller.new(request: REQUEST, source_path: "/x/fedora.img")
  expect(!other.send(:iso?), "img taken for an iso")
  "both answers correct"
end

check("fat_label sanitises the volume label") do
  expect(INSTALLER.send(:fat_label, "WIN11_TEST") == "WIN11_TEST", "label mangled")
  expect(
    INSTALLER.send(:fat_label, "Windows 11 Pro x64 Edition") == "WINDOWS11PR",
    "long label not trimmed to 11 characters",
  )
  expect(INSTALLER.send(:fat_label, "***") == "INSTALLER", "no fallback label")
  "sanitised"
end

check("extract_iso detects the Windows ISO and extracts it") do
  label = INSTALLER.send(:extract_iso)
  expect(label == "WIN11_TEST", "label #{label.inspect}")
  expect(File.file?(File.join(WORK_DIR, "sources", "install.wim")), "no extracted install.wim")
  label
end

check("extract_iso declines a UDF ISO that is not Windows") do
  tree = File.join(ROOT, "linuxtree")
  FileUtils.mkdir_p(tree)
  File.binwrite(File.join(tree, "vmlinuz"), "L" * 2048)
  iso = File.join(ROOT, "linux.iso")
  write_iso("FEDORA", iso, tree)
  other = Impression::WindowsInstaller.new(request: REQUEST, source_path: iso)
  expect(other.send(:extract_iso).nil?, "mistaken for Windows")
  "declined"
end

check("extract_iso declines an ISO9660-only image libudf cannot read") do
  tree = File.join(ROOT, "iso9660tree")
  FileUtils.mkdir_p(tree)
  File.binwrite(File.join(tree, "vmlinuz"), "L" * 2048)
  iso = File.join(ROOT, "iso9660.iso")
  write_iso(
    "DEBIAN",
    iso,
    tree,
    udf: false,
  )
  other = Impression::WindowsInstaller.new(request: REQUEST, source_path: iso)
  expect(other.send(:extract_iso).nil?, "mistaken for Windows")
  "declined"
end

check("dir_byte_total sums the extracted tree") do
  total = INSTALLER.send(:dir_byte_total, WORK_DIR)
  expect(total == TOTAL_BYTES, "total #{total}")
  total
end

check("build_fat_image formats and fills the staged image") do
  INSTALLER.send(
    :build_fat_image,
    64 * 1024 * 1024,
    "WIN11_TEST",
    INSTALLER.send(:dir_byte_total, WORK_DIR),
  )
  staged = File.join(REQUEST.cache_dir, "impression-windows.img")
  expect(File.file?(staged), "no staged image")
  listing = mtools("mdir -i #{staged} -/ ::")
  # mdir prints the 8.3 name in columns, and a long name as it stands.
  ["install  wim", "bootx64  efi", "setup    exe", "ReallyLongInstallerName.xml"].each do |name|
    expect(listing.include?(name), "#{name} missing from image:\n#{listing}")
  end
  label = mtools("mlabel -i #{staged} -s ::")
  expect(label.include?("WIN11_TEST"), "label is #{label.inspect}")
  # Each entry is deleted as it is packed, so scratch never holds two copies.
  expect(Dir.children(WORK_DIR).empty?, "scratch not drained")
  expect(
    REQUEST.published.any? { |status| status.phase == :build_image },
    "no build progress published",
  )
  "image built, #{REQUEST.published.count} statuses published"
end

check("partition_size_for falls back to the whole drive") do
  size = INSTALLER.send(:partition_size_for, 1024)
  expect(size.zero?, "expected whole-drive 0, got #{size}")
  "0 for a device whose size cannot be read"
end

FileUtils.remove_entry(ROOT)

puts
case FAILURES.empty?
when true
  puts "all checks passed"
else
  puts "FAILURES: #{FAILURES.join(", ")}"
  exit 1
end
