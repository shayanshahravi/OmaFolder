# Changelog

All notable changes to OmaFolder are documented here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-15

### Added

- `bar-widget` folder icon with a badge count of folded widgets.
- Vertical drawer anchored to the folder, built on the shell's own `Panel` and
  `KeyboardPanel` so it follows the bar position on every monitor.
- Left click toggles a widget's active state; right click opens its panel through
  `omarchy-shell shell toggle`.
- 3000 ms hold to eject a widget back onto the bar, with a progress ring.
- 1500 ms hover tooltip with the widget's name, state and type.
- Drag to reorder inside the drawer, drag out to eject, and a manage view that
  lists the widgets still on the bar so they can be dragged in.
- Keyboard control: `j`/`k` or arrows, Enter, `x` to eject, `m` for the manage
  view, Escape to close.
- `bin/omafolder-state` engine: JSON state file, exact-position restore on eject,
  atomic writes and a `shell.json` backup per change.
- Idempotent `install.sh` (with `--local` for development) and `uninstall.sh`
  that returns every folded widget to the bar before removing the plugin.
- English and Persian documentation, MIT license, and a lint workflow.
