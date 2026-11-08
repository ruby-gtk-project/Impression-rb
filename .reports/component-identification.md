# Component identification — audit addendum

| | |
|---|---|
| Upstream | `main` @ `9126f73` |
| Port | `ruby` @ `883b8cf` |

The full per-file inventory already lives in `.reports/component-inventory.md`
and was re-walked for this audit (every upstream file re-opened against the
port file it claims to map to). That inventory's substance holds: every
upstream source file and every named region of `window.blp` has a
corresponding `lib/impression/*.rb`, and the mapping table is accurate.

This addendum records what the previous pass's own language obscured, and one
unit the previous pass didn't carry far enough.

## A component the previous inventory wrote around

`window.blp`'s template root carries `styles ["devel"]` on the window,
conditional on `PROFILE == "Devel"` (`src/window.rs:136`, and the whole
profile switch in `meson.build:34-42` that builds a second app under
`io.gitlab.adhami3310.Impression.Devel` with a version suffix and a visibly
different icon). The previous inventory recorded this as:

> `devel` (profile=Devel only — N/A in Ruby port, no profile build)

That is the construction `component-identification` and
`accountability-ensurance` both exist to catch: "N/A" asserts the component
cannot exist in Ruby. It can — it's a CSS class and a second GApplication ID,
neither of which needs a GObject subclass to express — and nothing in the port
builds it. There is no development-profile build at all:
`lib/impression/application.rb::APP_ID` is the single hardcoded production ID,
there is no `--profile`/`development` build option anywhere in
`impression-rb.gemspec`, `Rakefile`, `flake.nix` or `exe/`, and `devel` never
appears as a CSS class in `lib/impression/style.rb`. This is a genuine,
if minor, missing component — see `accountability-ensurance.md`.

## Unit not previously carried to the scan: GSettings schema

The previous inventory lists `data/io.gitlab.adhami3310.Impression.gschema.xml.in`
as "ported" to `lib/impression/settings.rb`, true for the four keys and their
defaults, but the gschema file itself — and its four translatable `<summary>`
strings (`Window width`, `Window height`, `Window maximized state`, `List of
downloadable distros (distro_id, must_include, invert_must_include) tuples`)
— has no port-side counterpart at all. `Settings` is backed by a plain JSON
file instead of GSettings, which is a reasonable, explained substitution for
the *storage mechanism* (no schema install step needed to run from a
checkout) — but the four summary strings that exist only because the schema
file exists are a real translation-catalogue gap, found and confirmed in
`translation-parity.md`.

## Confirms, not new findings

- The window/dialog/page component counts in `.reports/component-inventory.md`
  were spot-checked against `origin/main:src/window.rs`,
  `src/application.rs`, `src/widgets/drag_overlay.rs`, `src/widgets/device_list.rs`
  and `data/resources/blueprints/window.blp`, and held in every case checked:
  action names, accelerators, `HANDLES_OPEN`, the shortcuts-dialog item list,
  the primary-menu item list, and the stylesheet (`data/resources/style.css`
  vs. `lib/impression/style.rb::CSS` — byte-identical rules).
- `lib/impression/application.rb`'s comment that "Adwaita::Application is
  broken in the Ruby bindings" and the app object is plain `Gtk::Application`
  with only the window as Adwaita is a documented binding limitation, not an
  excuse for a missing behaviour — `HANDLES_OPEN`, the `startup`/`activate`/
  `open` signals and the two accelerated actions are all still present and
  verified by `test/drive_metadata.rb`.
