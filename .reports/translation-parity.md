# Translation parity — Impression

| | |
|---|---|
| Upstream | `main` @ `9126f73` |
| Port | `ruby` @ `883b8cf` |
| Domain | `impression` (matches on both sides — `domain_matches: true`) |
| Upstream messages | 77 |
| Ported | 69 |
| Gaps | 8 |
| Extra (untranslated) | 0 |
| Upstream occurrences | 95 across 77 messages (9 reused) |
| Port occurrences | 71 (scanner) + several unresolved sites, manually resolved below |
| Upstream languages | 24 `.po` files, 1,609 translated, 15 untranslated, 7 fuzzy |
| Languages shipped by the port | 24 (`diff` of `po/*.po` basenames between upstream and port: identical) |
| Build command | `rake locale` (compiles `po/*.po` → `tmp/locale/*/LC_MESSAGES/impression.mo`, read via `lib/impression/i18n.rb`) |

Generated with `.claude/skills/translation-parity/scripts/catalogue.rb`
against `origin/main` (worktree at `/tmp/upstream-impression`, sha `9126f73`)
and the port's working tree (sha `883b8cf`). Raw comparison:
`summary.ported: 59`, `summary.gaps: 18`, `summary.unresolved (port): 16`.

**The raw scanner numbers are not the right numbers**, and reporting them
as-is would itself be the failure this skill exists to catch
("never write a ledger while `totals.unresolved` is non-zero"). The port's
16 unresolved markers were resolved by hand, per the skill's own worked
example for exactly this shape of call:

| Port site | Marker | Resolves to | Matches an upstream key? |
|---|---|---|---|
| `lib/impression/app_window.rb:38,125` | `_(TITLE)` | `TITLE = "Impression"` | yes |
| `lib/impression/erase_dialog.rb:15,35` | `_(HEADING)` | `HEADING = "Erase Drive?"` | yes |
| `lib/impression/erase_dialog.rb:16,47` | `_(BODY)` | `BODY = "You will lose all data stored on {}"` | yes |
| `lib/impression/stop_writing_dialog.rb:16,35` | `_(HEADING)` | `HEADING = "Stop Writing?"` | yes |
| `lib/impression/stop_writing_dialog.rb:17,35` | `_(BODY)` | `BODY = "This might leave the drive in a faulty state"` | yes |
| `lib/impression/open_dialog.rb:23,69` | `_(FILTER_NAME)` | `FILTER_NAME = "Disk Images"` | yes |
| `lib/impression/save_dialog.rb:17,63` | `_(FILTER_NAME)` | `FILTER_NAME = "Disk Images"` | yes (2nd call site) |
| `lib/impression/about_dialog.rb:27,34` | `_(name)`/`_(summary)` over `OTHER_APPS` | `"Footage"`, `"Polish your videos"`, `"Switcheroo"`, `"Convert and manipulate images"` | yes, all 4 |
| `lib/impression/notifier.rb:19,39` | `_(TITLE)` | `TITLE = "Impression"` | yes (same key as app_window's) |
| `lib/impression/primary_menu.rb:15,27` | `I18n.translate(label)` over `ITEMS` (not even a scanner-recognised marker name) | `"Keyboard Shortcuts"`, `"About Impression"` | yes, both |
| `lib/impression/status_view.rb:94-95` | `_(page[:title])`/`_(page[:description])` | the `PAGES`-style table's literal strings | yes (loading/no_devices/success/failure/flashing copy — already confirmed `ported` by the scanner for the strings it *could* follow) |

Every one of those resolves to a string that exists verbatim in upstream's
source, closing 10 of the scanner's 18 raw gaps. **8 gaps remain real** after
this hand resolution, and they are the number in the header above.

## The 8 real gaps

### Gap 1 — the shortcuts dialog's `msgctxt` is dropped (4 messages)

| msgctxt | msgid | Upstream site | Port site |
|---|---|---|---|
| `shortcut window` | `General` | `data/resources/blueprints/window.blp:420` | `lib/impression/shortcuts_dialog.rb:44` — `_(title)`, no context |
| `shortcut window` | `Open File` | `window.blp:423` | `shortcuts_dialog.rb:51` — `_(label)`, no context |
| `shortcut window` | `Show Shortcuts` | `window.blp:428` | `shortcuts_dialog.rb:51` |
| `shortcut window` | `Quit` | `window.blp:433` | `shortcuts_dialog.rb:51` |

Upstream marks all four `C_("shortcut window", "...")`. The English text the
port shows is byte-identical, which is exactly the failure mode this skill
exists to catch: it looks correct in every screenshot and is a different
gettext key on every other language's side, because `(nil, "General")` and
`("shortcut window", "General")` are different hash entries. Root cause:
`lib/impression/i18n.rb`'s whole `I18n`/`Gettext` module wraps only glibc's
plain `gettext()` — there is no `pgettext`/context-joined
(`context + "\x04" + msgid`) call anywhere in it, so there is currently no
way to mark a contextual string in this port at all, not just in this one
dialog. That is a structural gap, not a per-string typo.

### Gap 2-5 — the GSettings schema's four translatable summaries have no port-side home

| msgid | Upstream site |
|---|---|
| `Window width` | `data/io.gitlab.adhami3310.Impression.gschema.xml.in` |
| `Window height` | same |
| `Window maximized state` | same |
| `List of downloadable distros (distro_id, must_include, invert_must_include) tuples` | same |

`lib/impression/settings.rb` reimplements the same four keys and defaults
over a JSON file instead of GSettings — a reasonable, documented substitution
for the storage mechanism — but there is no `.gschema.xml.in` in the port at
all (confirmed: `find data -iname '*gschema*'` under the port returns
nothing), so these four `<summary>` strings, which exist only because that
file exists, have nowhere to be marked. These are real, not scanner noise.

## Languages

```
$ diff <(ls po/*.po | xargs -n1 basename) \
       <(git show origin/main:po/LINGUAS | tr ' ' '\n' | sed 's/$/.po/')
(no differences other than ordering)
```

24 `.po` files on both sides, same set, `LINGUAS` matches the file list on
both. `languages.translated_strings`/`untranslated_strings`/`fuzzy_strings`
report identically (1,609 / 15 / 7) because the port's `po/` is upstream's
`po/` copied verbatim — confirmed by `diff -r` returning nothing on the
`po/` directories' `.po`/`.pot`/`LINGUAS`/`POTFILES.in` contents.

`de` verified on screen this session via `test/drive_i18n.rb` (re-run, 8/8
checks passing), including the device page's Write button, the two
status-page labels, the flashing-phase copy, the erase dialog's body (with
upstream's `{}` placeholder intact) and the primary menu's two items.

## Occurrence mismatches (not a parity failure — a component-ledger pointer)

| msgid | Up uses | Port uses | Note |
|---|---:|---:|---|
| `Impression` | 7 | 5 | app title string, reused across window title / about dialog / notifier |
| `Do not remove the drive` | 3 | 2 | |
| `Writing` | 3 | 2 | |
| `Downloading Image` | 2 | 1 | |
| `Writing will begin once the download is completed` | 2 | 1 | |

All five are `ported` (the key is present and correct); per this skill, a use
mismatch is a `component-parity` question, not a translation one. Spot-check
of `Impression` (7→5): the two upstream sites it doesn't reuse are a log
line (`info!("Impression ({APP_ID})")`, not user-visible, correctly not
ported) and a second `window.set_title` call upstream makes redundantly
(same string, same site pattern) — not a user-visible gap. Not pursued
further here; flagged so a future `component-parity` pass can close it
formally rather than it sitting unexplained.

## Rules followed

- No upstream msgid was reworded. All 69 `ported` rows are byte-identical,
  confirmed by the generated `catalogue.rb --compare`, not by reading the
  Ruby and assuming.
- The 10 scanner-side "unresolved" gaps were resolved by hand per the skill's
  instruction, not left as phantom gaps nor silently waved through as passes.
- `totals.unresolved` is reported, not hidden: 16 raw unresolved sites on the
  port side, all 16 accounted for above (10 close to `ported`, the shortcuts
  dialog's missing context is folded into Gap 1 rather than counted as
  "unresolved" since the marker itself *is* readable — only its context
  argument is absent).
