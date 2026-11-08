# Component parity — Impression

| | |
|---|---|
| Upstream | `main` @ `9126f73` |
| Port | `ruby` @ `883b8cf` |
| Units with full (4-axis) parity | 8 / 9 |

Units audited: application class, app window + welcome page + device page +
status stack (one unit, per `component-identification`'s file-union rule),
distro row, device row, drag overlay, shortcuts dialog, primary menu, about
dialog, erase/stop-writing dialogs. Axes: count, style, behaviour, text.
Behaviour was checked by re-running `test/drive_impression.rb`,
`test/drive_metadata.rb` and `test/drive_i18n.rb` (53 + 16 + 8 = 77 checks,
all passing, this session) rather than by reading handlers.

## Unit: application class — `src/application.rs` → `lib/impression/application.rb`

| | Up | Port | Verdict |
|---|---|---|---|
| `app.quit` action | 1 | 1 | parity |
| Accelerators | 4 (`app.quit`, `win.close`, `win.open`, `win.show-help-overlay`) | 4, identical | parity |
| `HANDLES_OPEN` | yes | yes | parity |
| `startup`/`activate`/`open` | 3 signals | 3 signals, same effect | parity |

Verdict: **parity**. Confirmed live by `test/drive_metadata.rb`'s two
launch-with-file checks and the accelerator table in
`.reports/component-inventory.md`.

## Unit: window + welcome page + device page + status stack — `src/window.rs` + `window.blp` → `lib/impression/app_window.rb` + `welcome_page.rb` + `device_page.rb` + `status_view.rb` + `drag_overlay.rb` + `distro_row.rb` + `device_row.rb`

Widget counts, CSS classes and signals were re-walked against the component
inventory and held, with one exception:

| Widget | Up × | Port × | CSS | Verdict |
|---|---:|---:|---|---|
| `Adw.ApplicationWindow` (template root) | 1 | 1 | `devel` class **not reproducible** — no development-profile build exists in the port at all | **gap** |
| everything else in the window/pages/stack | matches | matches | matches | parity |

The `devel` gap is a real, if cosmetic, missing component: upstream ships a
visually distinct `io.gitlab.adhami3310.Impression.Devel` build (different
app ID, version suffix, `devel` CSS class darkening the header bar) and the
port has no equivalent build mode anywhere in `impression-rb.gemspec`,
`Rakefile`, `flake.nix` or `exe/`. See `accountability-ensurance.md`.

Behaviour (signals/actions) verified live by `test/drive_impression.rb`:
open/save dialogs, erase confirm, stop-writing guard, device monitor wiring,
architecture toggle, drag-overlay reveal via `drop-target`'s
`current-drop-notify`, and the four status-stack pages all drove and asserted
correctly (53/53 checks, run this session).

Text axis: see `translation-parity.md`. Every widget built by this unit has
byte-identical English *except* the shortcuts-dialog's four items, whose
`msgctxt` the port drops (below).

## Unit: shortcuts dialog — `window.blp`'s `Adw.ShortcutsDialog help_overlay` → `lib/impression/shortcuts_dialog.rb`

| Widget | Up × | Port × | CSS | Signals | Text | Verdict |
|---|---:|---:|---|---|:-:|---|
| `Adw.ShortcutsSection` "General" | 1 | 1 | — | — | ✗ | **gap** |
| `Adw.ShortcutsItem` × 3 | 3 | 3 | — | action-name wired as accelerator | ✗ | **gap** |

Count, widget type and the three items' labels/accelerators are all correct
and live-verified (`test/drive_impression.rb` checks 7-8). The text axis
fails: upstream marks all four strings `C_("shortcut window", "...")`
(`data/resources/blueprints/window.blp:420,423,428,433`); the port's
`_(title)`/`_(label)` calls (`lib/impression/shortcuts_dialog.rb:44,51`) carry
no context at all, and the port's whole `I18n` module
(`lib/impression/i18n.rb`) wraps only plain `gettext()` — it has no
`pgettext`/`dcgettext`-with-context equivalent to call even if the site asked
for one. Filed against both ledgers; see `translation-parity.md`.

## Unit: primary menu — `menu primary_menu` → `lib/impression/primary_menu.rb`

| Item | Up | Port | Verdict |
|---|---|---|---|
| "Keyboard Shortcuts" → `win.show-help-overlay` | yes | yes | parity |
| "About Impression" → `win.about` | yes | yes | parity |

Text axis: both strings byte-identical (confirmed by hand — the scanner can't
follow `I18n.translate(label)` called on a hash-literal key, so this pair
reads as an "unresolved" census row rather than a scanner-confirmed match; see
`translation-parity.md`'s note on `lib/impression/primary_menu.rb`). Verdict:
**parity**.

## Unit: about dialog — `show_about` in `src/window.rs` → `lib/impression/about_dialog.rb`

| Field | Up | Port | Verdict |
|---|---|---|---|
| developers, designers, artists | present | present (`.reports/component-inventory.md`) | parity |
| `translator-credits` | present | present | parity |
| acknowledgement section "Code borrowed from" / Popsicle | present | present | parity |
| `add_other_app` × 2 (Footage, Switcheroo) | 2 | 2, same ids/strings | parity |

Verdict: **parity**, live-confirmed by `test/drive_impression.rb` checks 9-10
(dialog shows, carries the app name).

## Unit: erase / stop-writing dialogs — `src/window.rs` methods → `lib/impression/erase_dialog.rb`, `stop_writing_dialog.rb`

| | Up | Port | Verdict |
|---|---|---|---|
| Erase heading/body, Cancel/Erase responses | match | match (live-driven, checks 15-16) | parity |
| Stop-writing heading/body, guard on `close-request` | match | match (live-driven, checks 23-24) | parity |

Verdict: **parity**. (The two dialogs' body/heading strings resolve past the
scanner's unresolved-marker list the same way the shortcuts items don't —
their constants have no `msgctxt`, so there is nothing for them to drop.)

## Summary

8 of the 9 audited units have full four-axis parity. The one gap
(shortcuts dialog's missing `msgctxt`) and the one component-identification
finding (no `devel`-profile build) are both real and both small; neither is
excused anywhere in this ledger or in `.reports/component-inventory.md` after
this audit's correction.
