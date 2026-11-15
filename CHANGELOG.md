# Changelog

All notable changes to OmaFolder are documented here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Folded icons are centred in the collapsed 32 px strip, and a list row's label
  starts after the icon column instead of running over the icon.
- Opening a folded widget's panel no longer throws the widget out of the folder:
  the row is lent to the bar only while its panel is up (`expose`/`conceal`) and
  comes back to the folder as soon as the panel closes.

## [1.1.0] - 2026-11-15

### Fixed

- Left click on a folded row now opens that widget's panel. A folded widget has
  no live bar instance, so the drawer ejects it back onto the bar first and then
  summons the panel on the real instance instead of failing with "unknown" and a
  notice.
- The drawer no longer clips its first row: the card height is built from exact
  section heights (strip, `+`, list, update prompt, notice) instead of implicit
  layout heights, and the card grows upward as the list opens.
- The `+` button opens the plugin list directly underneath it, and the drawer
  grows upward to fit the rows. Long lists and long folders scroll instead of
  running past the screen.
- Icons drew as literal `\uf111` text: the glyph table in `Model.js` was
  double-escaped and is now a normal escape.
- `IpcHandler` is registered once, by the first screen's bar widget, and every
  route relays to the other monitors' instances. This removes the
  `Handler was registered but will not be used because another handler is
  registered for target io.github.shayanshahravi.omafolder` warning and makes IPC
  work on every monitor.

### Changed

- With the `+` view open the folded rows show their full names too, left-aligned
  in the same icon column and padding as the rows below the `+`.
- Right-click menu entries for widgets without a panel are no longer greyed out:
  "Open panel" now works for them through the eject-then-summon path.
- `README.md` and `README.fa.md` rewritten: accurate left-click, `+`/`×`,
  right-click and tooltip documentation in both languages.

### Removed

- Every remaining drag-and-drop reference, including the documentation, the live
  test suite and its `--live` flag. The drawer is click and keyboard only.

## [1.0.0] - 2026-11-15

### Added

- `bar-widget` folder icon with a badge count of folded widgets.
- Vertical 32 px drawer anchored to the folder, built on the shell's own `Panel`
  and `KeyboardPanel` so it follows the bar position on every monitor, and slides
  up out of the bar when it opens.
- Left click on an icon opens that widget's own panel.
- Right-click menu per icon: open panel, activate/deactivate, move up, move down,
  eject to bar.
- 1500 ms hover tooltip with the widget's name, state and type.
- Keyboard control: `j`/`k` or arrows, Enter, `x` to eject, `m` for the manage
  view, Escape to close.
- Per-plugin update check against the official Omarchy plugin market, with a
  confirmation step before anything is installed.
- `tests/run.sh` (model logic, QML syntax, state engine) and
  `tests/engine.test.py` for the state engine.
- `bin/omafolder-state` engine: JSON state file, exact-position restore on eject,
  atomic writes and a `shell.json` backup per change.
- Idempotent `install.sh` (with `--local` for development) and `uninstall.sh`
  that returns every folded widget to the bar before removing the plugin.
- English and Persian documentation, MIT license, and a lint workflow.
