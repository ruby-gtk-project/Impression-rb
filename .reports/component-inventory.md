# Impression — upstream component inventory

Upstream: `origin/main` in this repo (Rust / gtk-rs + libadwaita, one blueprint).
Port: the `ruby` branch. Scanned with
`.claude/skills/component-identification/scripts/component-scan.sh`.

Totals from the scan: upstream **52 widget rows / 18 CSS classes / 7 signals /
8 actions / 2 controllers** across 5 source files; the `ruby` branch has
**4 widget rows, 0 CSS classes, 1 signal, 0 actions** — the scaffold window
only. Effectively nothing of the app exists yet.

The whole UI is one blueprint, `data/resources/blueprints/window.blp`, bound to
`src/window.rs` (996 lines) by `CompositeTemplate`. Those two files are one
component *set*; the port splits them by page, because a single
`lib/app_window.rb` carrying all three stacks would be unreadable.

House shape note: the pilot port (`gnome-contacts-rb`) keeps flat
`lib/<thing>.rb` files with top-level classes and `lib/<app>.rb` as the entry
point. The `ruby` branch currently has the kettle-jem gem skeleton instead
(`lib/impression.rb` → `lib/impression/application.rb`, `module Impression`).
Targets below are written flat (`lib/application.rb`, …) to match the house
shape; the one existing file is the scaffold that `lib/application.rb` replaces.

---

## src/main.rs + src/application.rs — the application object

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Adw.Application` | 1 | — | `activate`, `startup`, `open` | `HANDLES_OPEN`; `resource-base-path` |
| `Gtk.Window.set_default_icon_name` | — | — | — | app id as icon name |

Actions installed: `app.quit`.
Accelerators set: `app.quit` `<Control>q`, `win.close` `<Control>w`,
`win.open` `<Control>o`, `win.show-help-overlay` `<Control>question`.
`main.rs` also does: gettext bind/textdomain, `set_application_name`,
GResource load, and `get_size_string` (MiB under 1024, else GiB with 2 dp).

→ `lib/application.rb` (actions, accels, open-file handling),
`lib/impression.rb` (entry: i18n + launcher), `lib/size_format.rb`.
**Present:** scaffold only, at `lib/impression/application.rb` — a status page
saying the port is unwritten. No actions, no accels, no open handling.

## window.blp (`template $AppWindow`) + src/window.rs — the window shell

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | `devel` (only when `PROFILE == "Devel"`) | `close-request` | default 500×600, min 360×294, title "Impression" |
| `Gtk.Stack main_stack` | 1 | — | — | crossfade; pages `choose` / `status` |
| `Adw.ToastOverlay toast_overlay` | 1 | — | — | hosts the status stack |
| `Adw.Toast` | 1 | — | — | _("File is not a Disk Image") on a bad drop/open |
| `Gtk.DropTarget` (controller) | 1 | — | `drop` | `file-drop-target`, `COPY`, `GdkFileList`; handed to the DragOverlay |

Actions installed on the window: `win.close`, `win.about`,
`win.show-help-overlay`, `win.open`.
Behaviour: `close-request` saves window size, and when a write is running it
raises the "Stop Writing?" dialog and vetoes the close. State held:
selected device object path, selected disk image (`Local{path,compression}` /
`Online{url,download_path,name}`), available devices, `is_running`.

→ `lib/app_window.rb`. **Missing.**

## window.blp — NavigationView, page `welcome` — the image chooser

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.NavigationView navigation` | 1 | — | — | pages `welcome`, `device_list`; `push_by_tag("device_list")` |
| `Adw.NavigationPage` | 1 | — | — | tag `welcome`, title _("Impression") |
| `$DragOverlay drag_overlay` | 1 | — | — | title _("Drop Here to Open") |
| `Adw.ToolbarView` + `Adw.HeaderBar` | 1+1 | — | — | — |
| `Gtk.MenuButton` | 1 | — | — | `open-menu-symbolic`, `primary_menu`, tooltip _("Main Menu"), primary |
| `Adw.PreferencesPage` | 1 | — | — | inside a vertical `Gtk.Box` (spacing 12) |
| `Gtk.Image` (app icon) | 1 | `app_icon` | — | `io.gitlab.adhami3310.Impression`, 128px via CSS |
| `Gtk.Label` | 1 | `title`, `title-1` | — | _("Choose Image") |
| `Adw.ActionRow open_image_button` | 1 | — | `activated` → `open_dialog` | _("Open File…"), activatable widget = `next_icon`; **grabs focus** on window create and after Finish |
| `Gtk.Image next_icon` | 1 | — | — | `go-next-symbolic` |
| `Adw.PreferencesGroup` | 1 | — | — | title _("Direct Download") |
| `Gtk.DropDown architecture` | 1 | `architecture` | `notify::selected` → `on_architecture_changed` | `Gtk.StringList` x86_64 / aarch64; insensitive until distros load |
| `Gtk.Box download_spinner` | 1 | `card`, `loading-frame` | — | holds a 32×32 spinning `Gtk.Spinner` |
| `Gtk.Box offline_screen` | 1 | `card` | — | hidden by default |
| `Adw.StatusPage` (offline) | 1 | `dim-label` | — | _("No Connection") / _("Connect to the internet to view available images") |
| `Gtk.Box distros` | 1 | — | — | hidden by default |
| `Gtk.ListBox amd_distros` | 1 | `boxed-list` | — | selection none |
| `Gtk.ListBox arm_distros` | 1 | `boxed-list` | — | selection none, hidden until aarch64 picked |
| `Adw.ActionRow` (distro row) | **repeater** | — | `activated` → `save_dialog` | one per `DistroRelease`; title = name, subtitle = version, suffix `Gtk.Image go-next-symbolic` as activatable widget |

Conditional/retry behaviour: a 10-second local timeout re-runs `get_distros`
while the welcome page is showing and `offline_screen` is visible. An empty
`downloadable-distros` setting clears both lists and hides spinner *and*
offline screen.

→ `lib/welcome_page.rb` + `lib/distro_row.rb`. **Missing.**

## window.blp — NavigationView, page `device_list` — pick a drive

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.NavigationPage` | 1 | — | — | tag `device_list`, title _("Impression") |
| `Adw.ToolbarView` + `Adw.HeaderBar` + `Gtk.MenuButton` | 1 each | — | — | same primary menu button as the welcome page |
| `Adw.PreferencesPage` | 1 | — | — | `valign: center` |
| `Gtk.Image` | 1 | `dim-label` | — | `media-optical-cd-symbolic`, 64px |
| `Gtk.Label name_value_label` | 1 | `title-3` | — | image file name (or online image name), wrap word-char, 3 lines, 24 chars |
| `Gtk.Label size_label` | 1 | `caption` | — | `get_size_string` of the local file; empty for online images |
| `Adw.Clamp` | 1 | — | — | max 450, tightening 200 |
| `Gtk.ListBox available_devices_list` | 1 | `boxed-list` | — | selection none; rebuilt from the device monitor |
| `Adw.PreferencesGroup` | 1 | — | — | description _("All data on the selected drive will be erased") |
| `Gtk.Button flash_button` | 1 | `destructive-action`, `pill` | `clicked` → `flash_dialog` | _("Write"); sensitive only while a device is selected |

→ `lib/device_page.rb`. **Missing.**

## window.blp — `Gtk.Stack stack` under the toast overlay — the status views

One `Adw.ToolbarView` + `Adw.HeaderBar` + `Gtk.MenuButton` wrapper, then five
stack pages (crossfade):

| Page | Widget | CSS | Signals | Notes |
|---|---|---|---|---|
| `loading` | `Gtk.Spinner loading_spinner` | — | — | 28×28, centred |
| `no_devices` | `Adw.StatusPage` | — | — | app icon, _("No Drives") / _("Insert a drive to write to") |
| `success` | `Adw.StatusPage` | — | — | `check-round-outline-symbolic`, _("Writing Completed") / _("The drive can be safely removed") |
| `success` | `Gtk.Button done_button` | `suggested-action`, `pill` | `clicked` → `done_clicked` | _("Finish"); clears devices, shows `no_devices`, refocuses Open File |
| `failure` | `Adw.StatusPage` | — | — | `error-symbolic`, _("Writing Unsuccessful") |
| `failure` | `Adw.Clamp` / `Gtk.ScrolledWindow` | `card` | — | max 600/400; min-content 100, max-content 200 |
| `failure` | `Gtk.Label error_message_label` | `monospace`, `error-message` | — | the flash error text; hidden when empty |
| `failure` | `Gtk.Button try_again_button` | `suggested-action`, `pill` | `clicked` → `try_again_clicked` | _("Retry") → back to `choose` |
| `flashing` | `Adw.StatusPage flashing_page` | — | — | title/description/icon swapped per `FlashPhase` (see below) |
| `flashing` | `Gtk.ProgressBar progress_bar` | — | — | `show-text`; `set_text(nil)` for a fraction, `""` + `pulse` for a pulse |
| `flashing` | `Gtk.Button cancel_button` | `pill` | `clicked` → `cancel_clicked` | _("_Cancel"), underline |

`FlashPhase` → page strings, all six: Download _("Downloading Image") /
_("Writing will begin once the download is completed") /
`folder-download-symbolic`; Extract _("Extracting Image") /
_("Reading the source image") / `media-optical-cd-symbolic`; ProcessImage
_("Processing Image") / _("Splitting the install image") /
`media-optical-cd-symbolic`; Partition _("Partitioning Drive") /
_("Do not remove the drive") / `usb-stick-symbolic`; BuildImage
_("Preparing Installer Image") / _("Building the installer filesystem") /
`flash-symbolic`; Copy _("Writing") / _("This could take a while") /
`flash-symbolic`.

A device change arriving while `flashing` / `failure` / `success` is visible
must **not** navigate away — upstream guards this explicitly.

→ `lib/status_view.rb`. **Missing.**

## window.blp — `menu primary_menu`

Two items in one section: _("Keyboard Shortcuts") → `win.show-help-overlay`,
_("About Impression") → `win.about`. Used by all three header bars.

→ `lib/primary_menu.rb`. **Missing.**

## window.blp — `Adw.ShortcutsDialog help_overlay`

One `Adw.ShortcutsSection` C_("shortcut window", "General") with three
`Adw.ShortcutsItem`: Open File → `win.open`, Show Shortcuts →
`win.show-help-overlay`, Quit → `app.quit`. Presented by
`win.show-help-overlay`.

→ `lib/shortcuts_dialog.rb`. **Missing.**

## src/widgets/drag_overlay.rs — drop target overlay

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (subclass) | 1 | css **name** `dragoverlay` | — | properties `title`, `child`, `drop-target` |
| `Gtk.Overlay` | 1 | — | — | parented directly to the bin; holds the real child |
| `Gtk.Revealer` | 1 | — | — | crossfade, `can-target: false`, hidden |
| `Adw.StatusPage` | 1 | `drag-overlay-status-page` | — | `document-send-symbolic`, title from the `title` property |
| `Gtk.DropTarget` (controller) | 1 | — | `notify::current-drop` | reveals the overlay while a drop hovers; re-settable, old handler disconnected |

→ `lib/drag_overlay.rb`. **Missing.**

## src/widgets/device_list.rs — one row per writable drive

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ActionRow` | **repeater** | — | — | title = drive label, subtitle = UDisks one-liner, activatable widget = its check button |
| `Gtk.CheckButton` | **repeater** | `selection_mode` | `toggled` | `valign: center`, radio-grouped to the first; prefix of the row |

Selection rules: all check buttons share the first one's group; with exactly
one device the toggle re-asserts `active = true`; the previously selected
device (matched by display string) stays selected, otherwise the first row is
selected and `flash_button` becomes sensitive.

Also in this file, not UI: UDisks2 enumeration (removable drives only, sorted
by object path), `DeviceMetadata` (object, display string, one-liner info,
label), label composition `"{id_label} ({vendor} {model})"` falling back to
`"{vendor} {model}"`, and `monitor_devices` — an ObjectManager
`InterfacesAdded`/`InterfacesRemoved` subscription with a 500 ms debounce.

→ `lib/device_row.rb` (the rows) and `lib/device_monitor.rb` (UDisks + the
debounce). **Both missing.**

## src/window.rs — dialogs

| Component | Widget | Responses | Notes |
|---|---|---|---|
| Erase confirmation (`flash_dialog`) | `Adw.AlertDialog` | `cancel` _("_Cancel"), `erase` _("_Erase") destructive | _("Erase Drive?") / _("You will lose all data stored on {}") with the device display string; `erase` starts the flash |
| Stop confirmation (`cancel_request`) | `Adw.AlertDialog` | `cancel` _("_Cancel"), `stop` _("_Stop Writing") destructive | _("Stop Writing?") / _("This might leave the drive in a faulty state"); closes the window when raised from `close-request`, else returns to `choose` |
| Open image (`open_dialog`) | `Gtk.FileDialog` + `Gtk.FileFilter` | — | modal; mime `x-iso9660-image`, `x-raw-disk-image`, `x-cd-image`; patterns `*.iso *.img *.iso.xz *.img.xz *.raw.xz`; filter name _("Disk Images") |
| Save download (`save_dialog`) | `Gtk.FileDialog` + `Gtk.FileFilter` | — | modal; patterns `*.img *.iso`; initial name = last URL segment or `disk-image.img` |
| About (`show_about`) | `Adw.AboutDialog` | — | built `from_appdata` upstream; developers, designers, artists, translator-credits, acknowledgement _("Code borrowed from") Popsicle, and two other apps (Footage, Switcheroo) |

→ `lib/erase_dialog.rb`, `lib/stop_writing_dialog.rb`, `lib/open_dialog.rb`,
`lib/save_dialog.rb`, `lib/about_dialog.rb`. **All missing.**

## Non-widget components the UI depends on

| Upstream | → port | What it is |
|---|---|---|
| `data/io.gitlab.adhami3310.Impression.gschema.xml.in` | `lib/settings.rb` | `window-width` 500, `window-height` 600, `is-maximized` false, `downloadable-distros` `a(smsb)` with 7 defaults (archlinux.org, endlessos.com, fedoraproject.org/Silverblue inverted, manjaro.org, opensuse.org, ubuntu.com, ubuntu.com/LTS) |
| `data/resources/style.css` | `lib/style.rb` + the stylesheet | 6 rules: `.loading-frame`, `.architecture button:not(:hover)`, `.app_icon`, `.drag-overlay-status-page`, `.error-message` |
| `data/resources/resources.gresource.xml` + `icons/` | asset load in `lib/application.rb` | 7 bundled action icons (`check-round-outline`, `error`, `flash`, `image-missing`, `paper`, `usb-stick`, `view-refresh`) and 2 other-app icons the About dialog shows |
| `src/online.rs` | `lib/online.rb` + `lib/distro_release.rb` | `db.libosinfo.org/latest.json` → osinfo-db tarball → roxmltree parse → `DistroRelease{name, version, url, variant}`, filtered by must-contain/invert, prerelease dropped, releases within 2 years (or rolling) |
| `src/flash/mod.rs` | `lib/flash_request.rb`, `lib/flash_status.rb` | download with 250 ms progress ticks, xz extract, unmount partitions, open the block device, copy with progress, rescan + eject, `FlashPhase`/`Progress::{Fraction,Pulse}`/`FlashStatus::{Active,Done}`, cancellation |
| `src/flash/windows_installer.rs` | `lib/windows_installer.rb` | the Windows-ISO path: partition, split oversized install.wim, build a FAT32 image |
| `src/flash/udf.rs` | `lib/udf.rb` | UDF reader used to pull files out of a Windows ISO |
| `src/flash/wim.rs` | `lib/wim.rb` | WIM image size/split arithmetic |
| `src/window.rs` `send_notification` | `lib/notifier.rb` | XDG notification portal; _("Image Written") / _("Failed to write image"), only when the window is inactive |
| `data/…desktop.in.in` | packaging | `Exec=impression %u`, `DBusActivatable`, mime types, keywords |
| `po/` (24 languages, 78 msgids, `impression.pot`) | `po/` kept as-is | translation parity is its own step |

## Blockers found while surveying

1. **No UDisks binding for Ruby, and no `dbus` gem in the dev shell.** The
   device list, unmount, rescan and eject all go through UDisks2 over D-Bus.
   Either add `ruby-dbus` to the Gemfile/`gemset.nix` or drive `udisksctl`
   as a subprocess; the choice shapes `lib/device_monitor.rb`.
2. **No XML parser in the dev shell** — `rexml` and `nokogiri` both fail to
   require. `lib/online.rb` needs one (osinfo-db is XML).
3. **`Adwaita::AboutDialog.from_appdata` is not bound** (checked in the dev
   shell; `add_other_app` and `add_acknowledgement_section` are). The About
   dialog has to be populated field by field from the metainfo values.
4. **No tokio.** Every `runtime().spawn` becomes a Ruby thread plus
   `GLib::Idle`/`timeout_add`; the 1-second progress poll and the 10-second
   offline retry map onto `GLib.timeout_add_seconds` directly.
5. **Windows-installer support is ~1 100 lines of byte-level Rust**
   (`udf.rs`, `wim.rs`, `windows_installer.rs`) and carries four of the six
   `FlashPhase` values. It is the single largest unit; the UI is cheap by
   comparison.
6. **Gem-skeleton vs house shape.** `lib/impression/application.rb` under
   `module Impression` is not the flat `lib/<thing>.rb` shape the pilot uses.
   Decide once, before the first real file lands.

All widget types the port needs are present in the bindings — probed in the
dev shell: every `Adwaita::*` and `Gtk::*` type named above resolves, and
`Gtk::ListBox#remove_all` exists.
