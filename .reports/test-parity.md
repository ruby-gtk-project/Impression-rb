# Test parity — Impression

| | |
|---|---|
| Upstream | `main` @ `9126f73` |
| Port | `ruby` @ `883b8cf` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |

Upstream has no test suite. Verified directly against `origin/main`, not
inferred from the port's own claims:

```
$ git ls-tree -r --name-only origin/main | grep -i test
(no output)
$ git show origin/main:src/flash/mod.rs | grep -n '#\[test\]\|cfg(test)'   # and every other src/*.rs
(no output in any of application.rs, window.rs, online.rs,
 widgets/device_list.rs, widgets/drag_overlay.rs,
 flash/{mod,udf,wim,windows_installer}.rs)
```

No `tests/` directory, no `#[test]`/`#[cfg(test)]` anywhere in `src/`, no test
target in `meson.build`/`Cargo.toml`. Parity is 0/0 and is met trivially.
**The port therefore inherits no safety net from upstream** — this is a
Rust/gtk-rs app that was never test-covered, and every check below was
written for the port and pins nothing upstream considered worth pinning.

## Extra

Driven and re-run live this session, under
`nix develop --command xvfb-run -a ruby <script>`:

- `test/drive_impression.rb` — **53 of 53 checks passed.** Window build,
  welcome page's three download states, architecture toggle, shortcuts/about
  dialogs, file-open accept/reject, device-row/monitor wiring, erase dialog,
  the full write pipeline through a real (not mocked) failure, the notifier,
  retry, and the stop-writing close-guard.
- `test/drive_i18n.rb` — **8 of 8 checks passed.** Catalogue lookup, a known
  translated string, pass-through for an unknown key, three widget-level
  translated strings, and the primary menu's two items, under
  `LANGUAGE=de`.
- `test/drive_metadata.rb` — **16 of 16 checks passed.** Desktop entry,
  MIME types, metainfo, D-Bus service file, and the open/present-only launch
  paths.
- `test/drive_windows_installer.rb` — **18 of 18 checks passed.** UDF image
  reading, WIM splitting (including cancellation and a deliberately bad
  input), the Windows-ISO detection/decline paths, and the FAT image build
  (`mkfs.vfat`/`mcopy`).

Total: **95 of 95 checks passed** across the four driver scripts, all
re-executed this session, not taken on the prior report's word.

## A real gap this ledger exists to catch: the RSpec harness has never run

`spec/` holds two files — `spec_helper.rb` and `README.md` — and zero example
files, so there is no RSpec suite to have parity with upstream's (upstream has
none either). But the harness itself does not run, and the previous round's
`.reports/ui-drive.md` wrote this finding in exactly the laundered form this
audit's `accountability-ensurance.md` calls out — "pre-existing kettle-jem
scaffolding, unrelated to the Ruby GTK4 port" and "nothing is actually
untested by this gap." That is true about *today's* `spec/` holding no tests,
and it is irrelevant to the actual defect: the moment anyone adds a real spec
file, `rake spec` / the dev-shell's own spec command still fails before a
single example runs.

Re-run this session, verbatim:

```
$ nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
...
Failure/Error: require "kettle/test/rspec"
LoadError: cannot load such file -- kettle/test/rspec
```

`spec/spec_helper.rb` requires `kettle-test`/`kettle-family`
(`impression-rb.gemspec:144`), which `nix/Gemfile` deliberately excludes
(it is "the app's RUNTIME gems... must not end up in a packaged app's
closure," per its own header) and the devShell does not `bundle install` the
root `Gemfile` either. So the dev shell the task requires every invocation
go through (`nix develop --command xvfb-run -a ruby <script>`) **cannot run
the project's own declared spec command**, full stop, independent of whether
`spec/` has anything in it yet.

This is filed as a gap, not excused: "the suite has nothing in it anyway" is
not a reason the harness is allowed to be broken, and a future agent reading
only `.reports/ui-drive.md` would reasonably conclude the RSpec path is a
closed, inconsequential question rather than an unrun check sitting in front
of whatever tests land in `spec/` next.
