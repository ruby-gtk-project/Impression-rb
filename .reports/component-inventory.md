# Impression — upstream component inventory

Upstream: `origin/main` in this repo (Rust / gtk-rs + libadwaita, one blueprint).
Port: the `ruby` branch. Scanned with
`.claude/skills/component-identification/scripts/component-scan.sh`.

Scan totals, as of this survey:

| | widget rows | distinct types | CSS classes | signals | actions | controllers |
|---|---:|---:|---:|---:|---:|---:|
| upstream (`src/` + `data/`, 5 source files + 1 blueprint) | 52 | 33 | 18 | 7 | 8 | 2 |
| port (`lib/`, 30 files) | 55 | 30 | 16 (+1 behind a constant) | 15 | 1 (+7 built in a loop) | 1 |

The scan's `action` stream is unreliable on the port by design — `app.quit`
comes from a literal, the four `win.*` actions come from a `action(name)`
helper and the accelerators from the frozen `ACCELS` hash, so only one shows.
Read `lib/impression/application.rb` and `lib/impression/app_window.rb#setup_actions`
for the real set; both match upstream exactly (see below).

The whole upstream UI is one blueprint, `data/resources/blueprints/window.blp`,
bound to `src/window.rs` (996 lines) by `CompositeTemplate`. Those two files are
one component *set*; the port splits them by page, because a single
`app_window.rb` carrying all three stacks would be unreadable.

House shape note: the port kept the kettle-jem gem skeleton
(`lib/impression.rb` → `lib/impression/*.rb`, everything inside
`module Impression`) rather than the pilot's flat `lib/<thing>.rb`. That is the
decision in force; the targets below name the files that exist.

Every component below exists on `ruby`. What is left is listed under
**Remaining gaps**.

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

→ `lib/impression/application.rb` (actions, `ACCELS`, open-file handling, icon
search path, stylesheet install), `exe/impression` + `lib/impression.rb`
(entry), `lib/impression/size_format.rb`. **Present.** The port uses
`Gtk::Application` (the Adwaita one is unusable in these bindings) and loads
`data/icons` through `Gtk::IconTheme` instead of a GResource bundle.

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

→ `lib/impression/app_window.rb` (492 lines) and
`lib/impression/disk_image.rb` (the `Compression`/`DiskImage` pair).
**Present.** `Adwaita::ApplicationWindow` does work here when it is handed the
`Gtk::Application`. The `devel` CSS class is not reproduced — the port has no
profile split.

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

→ `lib/impression/welcome_page.rb` (271 lines) + `lib/impression/distro_row.rb`.
**Present.**

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

→ `lib/impression/device_page.rb`. **Present.**

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

→ `lib/impression/status_view.rb` (247 lines) +
`lib/impression/flash_status.rb` (the phases and `Progress`). **Present.**

## window.blp — `menu primary_menu`

Two items in one section: _("Keyboard Shortcuts") → `win.show-help-overlay`,
_("About Impression") → `win.about`. Used by all three header bars.

→ `lib/impression/primary_menu.rb`. **Present.**

## window.blp — `Adw.ShortcutsDialog help_overlay`

One `Adw.ShortcutsSection` C_("shortcut window", "General") with three
`Adw.ShortcutsItem`: Open File → `win.open`, Show Shortcuts →
`win.show-help-overlay`, Quit → `app.quit`. Presented by
`win.show-help-overlay`.

→ `lib/impression/shortcuts_dialog.rb`. **Present.**

## src/widgets/drag_overlay.rs — drop target overlay

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (subclass) | 1 | css **name** `dragoverlay` | — | properties `title`, `child`, `drop-target` |
| `Gtk.Overlay` | 1 | — | — | parented directly to the bin; holds the real child |
| `Gtk.Revealer` | 1 | — | — | crossfade, `can-target: false`, hidden |
| `Adw.StatusPage` | 1 | `drag-overlay-status-page` | — | `document-send-symbolic`, title from the `title` property |
| `Gtk.DropTarget` (controller) | 1 | — | `notify::current-drop` | reveals the overlay while a drop hovers; re-settable, old handler disconnected |

→ `lib/impression/drag_overlay.rb`. **Present** as a composed object rather
than a registered GObject subclass, so the `dragoverlay` CSS *name* is not
reproduced (nothing in upstream's stylesheet targets it). `drop_target=` does
not disconnect a previous handler, because the window sets it once.

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

→ `lib/impression/device_row.rb` (the rows) and
`lib/impression/device_monitor.rb` (UDisks + the debounce). **Present.** The
bindings have no UDisks client and `GetManagedObjects`' `a{oa{sa{sv}}}` reply
has no Ruby conversion, so the port enumerates through
`org.freedesktop.DBus.Introspectable` and reads properties through
`org.freedesktop.DBus.Properties` over `Gio::DBus`.

## src/window.rs — dialogs

| Component | Widget | Responses | Notes |
|---|---|---|---|
| Erase confirmation (`flash_dialog`) | `Adw.AlertDialog` | `cancel` _("_Cancel"), `erase` _("_Erase") destructive | _("Erase Drive?") / _("You will lose all data stored on {}") with the device display string; `erase` starts the flash |
| Stop confirmation (`cancel_request`) | `Adw.AlertDialog` | `cancel` _("_Cancel"), `stop` _("_Stop Writing") destructive | _("Stop Writing?") / _("This might leave the drive in a faulty state"); closes the window when raised from `close-request`, else returns to `choose` |
| Open image (`open_dialog`) | `Gtk.FileDialog` + `Gtk.FileFilter` | — | modal; mime `x-iso9660-image`, `x-raw-disk-image`, `x-cd-image`; patterns `*.iso *.img *.iso.xz *.img.xz *.raw.xz`; filter name _("Disk Images") |
| Save download (`save_dialog`) | `Gtk.FileDialog` + `Gtk.FileFilter` | — | modal; patterns `*.img *.iso`; initial name = last URL segment or `disk-image.img` |
| About (`show_about`) | `Adw.AboutDialog` | — | built `from_appdata` upstream; developers, designers, artists, translator-credits, acknowledgement _("Code borrowed from") Popsicle, and two other apps (Footage, Switcheroo) |

→ `lib/impression/erase_dialog.rb`, `lib/impression/stop_writing_dialog.rb`,
`lib/impression/open_dialog.rb`, `lib/impression/save_dialog.rb`,
`lib/impression/about_dialog.rb`. **All present.** `from_appdata` is not bound,
so About sets its fields directly.

## Non-widget components the UI depends on

| Upstream | → port | Present | What it is |
|---|---|---|---|
| `data/io.gitlab.adhami3310.Impression.gschema.xml.in` | `lib/impression/settings.rb` | yes | `window-width` 500, `window-height` 600, `is-maximized` false, `downloadable-distros` `a(smsb)` with 7 defaults (archlinux.org, endlessos.com, fedoraproject.org/Silverblue inverted, manjaro.org, opensuse.org, ubuntu.com, ubuntu.com/LTS) |
| `data/resources/style.css` | `lib/impression/style.rb` | yes | the same 6 rules, inline, installed at `PRIORITY_APPLICATION` |
| `data/resources/resources.gresource.xml` + `icons/` | `data/icons/` + the icon search path in `lib/impression/application.rb` | yes | 7 bundled action icons and 4 app icons, as a hicolor tree instead of a GResource bundle |
| `src/online.rs` | `lib/impression/online.rb`, `lib/impression/distro_release.rb`, `lib/impression/xml.rb` | yes | `db.libosinfo.org/latest.json` → osinfo-db tarball → XML parse → `DistroRelease{name, version, url, variant}`, filtered by must-contain/invert, prerelease dropped, releases within 2 years (or rolling). `xml.rb` is a hand-written reader because REXML is not in the runtime closure |
| `src/flash/mod.rs` | `lib/impression/flash_request.rb`, `lib/impression/flash_status.rb` | yes | download with progress ticks, xz extract, unmount partitions, open the block device, copy with progress, rescan + eject, phases/`Progress`/cancellation |
| `src/flash/windows_installer.rs` | `lib/impression/windows_installer.rb` | yes | the Windows-ISO path: partition, split oversized install.wim, build a FAT32 image |
| `src/flash/udf.rs` | `lib/impression/udf.rb` | yes | UDF reader used to pull files out of a Windows ISO |
| `src/flash/wim.rs` | `lib/impression/wim.rb` | yes | WIM image size/split arithmetic |
| `src/window.rs` `send_notification` | `lib/impression/notifier.rb` | yes | XDG notification portal; _("Image Written") / _("Failed to write image"), only when the window is inactive |
| `po/` (24 languages, `impression.pot`) | `po/` + `lib/impression/i18n.rb` | yes | the same 24 catalogues; `i18n.rb` binds libintl through Fiddle and `rake locale` compiles the `.mo` files |
| `data/…desktop.in.in`, `…metainfo.xml.in.in`, `…service.in` | `data/io.gitlab.adhami3310.Impression.desktop`, `….metainfo.xml`, `….service` | yes | the three metadata files with meson's `@icon@` / `@app-id@` / `@gettext-package@` substituted; `rake metadata` and the flake's install phase merge the `po/` translations in with `msgfmt --desktop` / `--xml` the way `i18n.merge_file` does, and point both `Exec` lines at the installed wrapper. `:handles_open` on the application object is what makes `%u` and `--gapplication-service` work |

## Remaining gaps

1. **The `devel` CSS class.** Upstream adds it to the window when
   `PROFILE == "Devel"` and ships a separate `.Devel` icon (which the port does
   carry). The port has no profile split, so the striped dev header never
   appears.
2. **The `dragoverlay` CSS name.** Upstream sets it in `class_init`; the port
   composes rather than subclasses, so the name is absent. Nothing in the
   stylesheet targets it, so this is cosmetic parity only.
3. **No specs.** `spec/` is empty and the dev shell's spec runner has nothing
   to run. `test/` holds three drive scripts (`drive_i18n.rb`,
   `drive_windows_installer.rb`, `drive_metadata.rb`) but none for the window,
   the welcome page, the device page or the status views.
4. **GSettings vs the port's settings store.** `lib/impression/settings.rb`
   reproduces the keys and defaults, but no compiled gschema is installed, so
   the values are not shared with anything else on the system that reads
   upstream's schema.

## Notes for later steps

- Upstream widget types absent from the port's scan are
  `Gtk.ApplicationWindow`, `Gtk.CompositeTemplate` and `Gtk.Widget` — template
  plumbing and a type reference, not components. Nothing in the widget stream
  is actually unported.
- `Gtk::VERSION` does not exist in these bindings; the constant is
  `Gtk::Version` (`4.22.4` in this dev shell).
