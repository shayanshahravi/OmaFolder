# Changelog

All notable changes to OmaFolder are documented here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-15

### Added

- `bar-widget` folder icon with a badge count of folded widgets.
- Vertical 32 px drawer anchored to the folder, built on the shell's own `Panel`
  and `KeyboardPanel` so it follows the bar position on every monitor, and slides
  up out of the bar when it opens.
- Left click on an icon opens that widget's own panel.
- Right-click menu per icon: open panel, activate/deactivate, move up, move down,
  eject to bar. Nothing changes on a plain click.
- Drag and drop with manual pointer tracking (Qt's internal drag does not start
  inside a layer-shell surface): drag inside the drawer to reorder, drag out to
  eject, drag from the manage view to fold a widget in. An insertion marker shows
  where the row will land, and releasing outside shows an eject hint.
- 1500 ms hover tooltip with the widget's name, state and type.
- Keyboard control: `j`/`k` or arrows, Enter, `x` to eject, `m` for the manage
  view, Escape to close.
- `tests/run.sh` (model logic, QML syntax, state engine) and `tests/run.sh --live`,
  which drives a real drag inside the running shell.
- `bin/omafolder-state` engine: JSON state file, exact-position restore on eject,
  atomic writes and a `shell.json` backup per change.
- Idempotent `install.sh` (with `--local` for development) and `uninstall.sh`
  that returns every folded widget to the bar before removing the plugin.
- English and Persian documentation, MIT license, and a lint workflow.
