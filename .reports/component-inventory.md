# Impression-rb component inventory

Surveyed against `origin/main` (gtk-rs/Vala-style Rust + blueprint upstream)
on 2026-11-07. Upstream is small: one window class (`src/window.rs`), two
custom widgets (`src/widgets/device_list.rs`, `src/widgets/drag_overlay.rs`),
one application class (`src/application.rs`), one blueprint
(`data/resources/blueprints/window.blp`) holding most of the UI tree, plus
`src/online.rs` (distro metadata fetch) and the `src/flash/*` write pipeline
(`mod.rs`, `udf.rs`, `wim.rs`, `windows_installer.rs`).

**Overall finding: the `ruby` branch already has a component for every
upstream source file and every named region of `window.blp`.** No missing
component was found. This report records the mapping and the per-component
widget/CSS/signal surface for the record, per the `component-identification`
skill.

## Application class

### `src/application.rs` → `lib/impression/application.rb` — EXISTS

- Kind: application class (actions, accelerators, main-window presentation).
- Actions: `app.quit`.
- Accelerators: `app.quit` (`<Control>q`), `win.close` (`<Control>w`),
  `win.open` (`<Control>o`), `win.show-help-overlay` (`<Control>question`).
- `open()` (file-open activation) hands the file to the window.

## Window and its pages

### `src/window.rs` + `data/resources/blueprints/window.blp` → `lib/impression/app_window.rb` — EXISTS

The window file and its blueprint are one component (per
`component-identification`'s file-union rule): the blueprint is the widget
tree (`Stack main_stack`, `Adw.NavigationView navigation`, `toast_overlay`,
`help_overlay`, `primary_menu`), the Rust file is the callbacks
(`setup_gactions`, `cancel_request`, `flash`, `update_flashing_page`,
`open_dialog`, `save_dialog`, `load_distros`, `show_about`,
`setup_device_monitor`, `load_devices_into_ui`, window-size save/restore).

| Widget | × | CSS | Signals/actions | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` (template root) | 1 | `devel` (profile=Devel only — N/A in Ruby port, no profile build) | `close-request` | top-level |
| `Gtk.Stack` (`main_stack`) | 1 | — | — | crossfade, pages `choose`/`status` |
| `Adw.NavigationView` (`navigation`) | 1 | — | — | pages `welcome`/`device_list` |
| `Adw.ToastOverlay` (`toast_overlay`) | 1 | — | — | "File is not a Disk Image" toast |
| `Adw.ShortcutsDialog` (`help_overlay`) | 1 | — | `win.show-help-overlay` presents it | see shortcuts component below |
| win actions | — | — | `win.close`, `win.about`, `win.show-help-overlay`, `win.open` | installed in `setup_gactions` |
| `Gtk.DropTarget` | 1 | — | `drop` (file open) | wired to `DragOverlay` |

Composite children (`welcome` page, `device_list` page, `status` stack pages,
dialogs, menu) are each their own component below — this file's job is to
own and wire them, matching the Ruby port's `app_window.rb`, which
`require_relative`s all of them and does the same composition.

## Composite components inside `window.blp` / `window.rs`

### Welcome page (`Adw.NavigationPage tag="welcome"`) → `lib/impression/welcome_page.rb` — EXISTS

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ToolbarView` + `Adw.HeaderBar` | 1 each | — | — | |
| `Gtk.MenuButton` | 1 | — | menu-model = primary menu | |
| `Adw.PreferencesPage` | 1 | — | — | |
| `Adw.PreferencesGroup` | 3 | — | — | icon/title, open row, direct-download |
| `Gtk.Image` (app icon) | 1 | `app_icon` | — | |
| `Gtk.Label` (title) | 1 | `title`, `title-1` | — | |
| `Adw.ActionRow` (`open_image_button`) | 1 | — | `activated` → `open_dialog` | |
| `Gtk.Image` (`next_icon`) | 1 | — | — | activatable widget of the row |
| `Gtk.DropDown` (`architecture`) | 1 | `architecture` | `notify::selected` → `on_architecture_changed` | x86_64/aarch64 |
| `Gtk.Box` (`download_spinner`) | 1 | `card`, `loading-frame` | — | |
| `Gtk.Spinner` | 1 | — | — | |
| `Gtk.Box` (`offline_screen`) | 1 | `card` | — | |
| `Adw.StatusPage` (offline) | 1 | `dim-label` | — | "No Connection" |
| `Gtk.Box` (`distros`) | 1 | — | — | |
| `Gtk.ListBox` (`amd_distros`, `arm_distros`) | 2 | `boxed-list` | — | populated via `DistroRow.load` |
| `$DragOverlay` | 1 | — | — | see below |

### Distro row (`src/window.rs` `load_distros`) → `lib/impression/distro_row.rb` — EXISTS

Repeater: one `Adw.ActionRow` per downloadable release (variable count).

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Adw.ActionRow` | 1/release | — | `activated` → opens save dialog |
| `Gtk.Image` (`go-next-symbolic`) | 1/release | — | activatable widget |

### Device-list page (`Adw.NavigationPage tag="device_list"`) → `lib/impression/device_page.rb` — EXISTS

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Adw.ToolbarView` + `Adw.HeaderBar` + `Gtk.MenuButton` | 1 each | — | — |
| `Adw.PreferencesPage`/`Group` | — | — | — |
| `Gtk.Image` (optical-disc icon) | 1 | `dim-label` | — |
| `Gtk.Label` (`name_value_label`) | 1 | `title-3` | — |
| `Gtk.Label` (`size_label`) | 1 | `caption` | — |
| `Adw.Clamp` | 1 | — | — | max 450 |
| `Gtk.ListBox` (`available_devices_list`) | 1 | `boxed-list` | — | populated via `DeviceRow.load` |
| `Gtk.Button` (`flash_button`) | 1 | `destructive-action`, `pill` | `clicked` → erase/flash dialog | starts disabled |

### Device row (`src/widgets/device_list.rs` `fn new`) → `lib/impression/device_row.rb` — EXISTS

Repeater: one row per device.

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Adw.ActionRow` | 1/device | — | — |
| `Gtk.CheckButton` | 1/device | `selection_mode` | `toggled` | grouped so only one selects; lone device can't deselect |

### Status stack (`Gtk.Stack stack`, inside `status` page) → `lib/impression/status_view.rb` — EXISTS

| Page | Widget | × | CSS | Signals |
|---|---|---:|---|---|
| `loading` | `Gtk.Spinner` | 1 | — | — |
| `no_devices` | `Adw.StatusPage` | 1 | — | — |
| `success` | `Adw.StatusPage` + `Gtk.Button` (`done_button`) | 1+1 | `suggested-action`,`pill` | `clicked`→`done_clicked` |
| `failure` | `Adw.StatusPage`, `Adw.Clamp`, `Gtk.ScrolledWindow`, `Gtk.Label` (`error_message_label`), `Gtk.Button` (`try_again_button`) | — | `card`/`monospace`,`error-message`/`suggested-action`,`pill` | `clicked`→`try_again_clicked` |
| `flashing` | `Adw.StatusPage` (`flashing_page`), `Gtk.ProgressBar`, `Gtk.Button` (`cancel_button`) | — | `pill` | `clicked`→`cancel_clicked` |

### DragOverlay (`src/widgets/drag_overlay.rs`) → `lib/impression/drag_overlay.rb` — EXISTS

Custom `Adw.Bin` subclass: `Gtk.Overlay` + `Gtk.Revealer` (crossfade) +
`Adw.StatusPage` (icon `document-send-symbolic`, css
`drag-overlay-status-page`), reveal toggled by `drop-target`'s
`current-drop-notify`. Properties `title`, `child`, `drop-target`.

### Dialogs (built in `src/window.rs` methods, not separate upstream files)

| Upstream method | Port file | Exists |
|---|---|---|
| `open_dialog` (`Gtk.FileDialog`, open) | `lib/impression/open_dialog.rb` | yes |
| `save_dialog` (`Gtk.FileDialog`, save) | `lib/impression/save_dialog.rb` | yes |
| `flash_dialog` (`Adw.AlertDialog`, erase confirm) | `lib/impression/erase_dialog.rb` | yes |
| `cancel_request` (`Adw.AlertDialog`, stop-writing confirm) | `lib/impression/stop_writing_dialog.rb` | yes |
| `show_about` (`Adw.AboutDialog`) | `lib/impression/about_dialog.rb` | yes |

### Shortcuts dialog (`Adw.ShortcutsDialog help_overlay` in `window.blp`) → `lib/impression/shortcuts_dialog.rb` — EXISTS

One section "General", three items: Open File (`win.open`), Show Shortcuts
(`win.show-help-overlay`), Quit (`app.quit`).

### Primary menu (`menu primary_menu` in `window.blp`) → `lib/impression/primary_menu.rb` — EXISTS

Two items: "Keyboard Shortcuts" (`win.show-help-overlay`), "About Impression"
(`win.about`).

## Non-widget upstream units (still ported)

| Upstream | Port file | Exists | Notes |
|---|---|---|---|
| `src/online.rs` (distro metadata/osinfo-db fetch) | `lib/impression/online.rb`, `lib/impression/distro_release.rb`, `lib/impression/xml.rb` | yes | |
| `src/flash/mod.rs` (write pipeline orchestration) | `lib/impression/flash_request.rb`, `lib/impression/flash_status.rb` | yes | |
| `src/flash/udf.rs` (libudf FFI) | `lib/impression/udf.rb` | yes | |
| `src/flash/wim.rs` (libwim FFI) | `lib/impression/wim.rb` | yes | |
| `src/flash/windows_installer.rs` | `lib/impression/windows_installer.rb` | yes | |
| `src/widgets/device_list.rs` (UDisks enumeration/monitor) | `lib/impression/device_monitor.rb` (uses `udisks` gem) + `lib/impression/device_row.rb` | yes | |
| `data/io.gitlab.adhami3310.Impression.gschema.xml.in` (GSettings: `window-width`, `window-height`, `is-maximized`, `downloadable-distros`) | `lib/impression/settings.rb` | yes | |
| `data/io.gitlab.adhami3310.Impression.metainfo.xml.in.in` (About dialog data: developers, designers, translator credits, related apps) | `lib/impression/about_dialog.rb` | yes | about_dialog.rb notes it sets the fields directly since there's no GResource bundle to read from |
| `po/*.po` (translation catalogue) | `lib/impression/i18n.rb` | yes (gettext wiring present; `translation-parity` skill covers catalogue completeness, not scoped to this survey) | |

## Gaps found

None at the component level. The previous pass through this report flagged
one seam: `lib/impression/udisks_bus.rb`'s write-pipeline operations (Format,
CreatePartitionAndFormat, Unmount, Rescan, Eject, OpenDevice, used by
`flash_request.rb` and `windows_installer.rb`) went over raw `Gio::DBusProxy`
rather than the `udisks` gem's typed `UDisks::Client`, on the stated theory
that `GetManagedObjects`'s `a{oa{sa{sv}}}` reply has no Ruby conversion and
that building an (inherently async) `UDisks::Client` from the write
pipeline's own thread was impractical.

This round fixed it: `udisks_bus.rb` is now entirely the typed client —
`Unmount`/`Rescan`/`Eject`/`OpenDevice`/`Format`/`CreatePartitionAndFormat`
are `call_*_sync` on the gem's generated `UDisks::Block`/`Filesystem`/
`Drive`/`PartitionTable` proxies, and property reads (`Size`, mount points,
partition-table presence) go through the same typed objects rather than raw
`org.freedesktop.DBus.Properties`/`.Introspectable`. The reply-conversion
objection doesn't hold: `UDisks::Client#object_manager` is exactly the thing
`device_monitor.rb` already uses for enumeration. The threading objection is
sidestepped rather than solved — `DeviceMonitor#connect_client` (main
thread, where the GTK main loop already runs and the async constructor's
callback fires naturally) now also publishes the client it builds to
`Impression::Udisks.client`, and the write pipeline's own thread only ever
makes blocking `call_*_sync` calls against that already-connected client, which
need no main loop of their own to complete. `lib/impression/xml.rb`'s
D-Bus Introspect parsing is no longer used by this module (it is still used
by `online.rb` for the osinfo-db XML, so the file stays).

## Gem wiring check (per task instructions)

- `require "udisks"` is present (`lib/impression/device_monitor.rb:4`) and is
  on a reachable, live code path (`App Window` → `setup_device_monitor` →
  `DeviceMonitor` → `UDisks::Client.new_for_connection`), not merely required.
- `impression-rb.gemspec` declares `spec.add_dependency("udisks", "~> 1.0")`.
- `nix/Gemfile` lists `gem "udisks"`; `nix/Gemfile.lock` has `udisks (1.0.0)`
  resolved.
- `flake.nix` includes `udisks2` in the typelib/build-inputs stack
  (`gtkStack`).
- No gemspec dependency is left unused by `lib/`.
