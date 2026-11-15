# OmaFolder

[فارسی (Persian)](README.fa.md)

**A folder on the Omarchy bar that holds the widgets you rarely need.** Fold a
bar widget into it and it leaves the bar; open the folder to get a vertical
drawer of what is inside and get it back out of the way.

Built for **Omarchy 4 (Quattro)**: a native Quickshell `bar-widget`, no Waybar
and no extra desktop process.

![OmaFolder drawer open above the bar](preview.png)

## Features

| Interaction | What happens |
|---|---|
| Left click on the folder | Opens or closes the vertical drawer (it slides up out of the bar) |
| Left click on a folded row | Runs that widget's primary action: opens its own panel. A widget that only exists on the bar (no panel plugin) is handed back to the bar and opened there |
| Left click on the **＋** button | Turns it 45° into **×**, widens the drawer and lists every bar widget that is not folded yet |
| Left click on a row under **×** | Folds that widget into the folder; the drawer stays open |
| **Right click on a folded row** | Action menu: open panel, activate/deactivate, move up, move down, check for update, eject to bar |
| Hover a row for 1.5 s | Tooltip with the widget's name, state and type |
| `j` / `k`, Enter, `x`, `m`, `c`, Escape | Keyboard: move, open, eject, `＋` view, update check, close |

While **×** is open the whole drawer grows to the width of a list and every row -
folded above **×** and available below it - shows its icon on the left and its
full name next to it, in the same column and the same padding. Clicking **×**
again collapses it back to the 32 px icon strip.

The drawer is a 32 px icon strip when closed: the icon keeps about a pixel of
space on each side. Everything that changes a widget - activate, deactivate,
reorder, eject - lives in the right-click menu, so a stray click never moves
anything.

A deactivated widget is dimmed in the drawer and its own panel is closed. Because
a folded widget has already left the bar there is no background output left to
suspend, and QML has no CSS `filter: grayscale()`, so "deactivated" is expressed
by dimming rather than a grayscale filter.

## Install

```sh
omarchy plugin add https://github.com/shayanshahravi/OmaFolder.git --enable
```

or from a checkout:

```sh
./install.sh           # clone and enable
./install.sh --local   # install this working tree instead (for development)
```

`install.sh` backs up `~/.config/omarchy/shell.json`, creates
`~/.config/omafolder/state.json`, enables the plugin and places the folder on the
left of the bar when it is not there yet. Running it again updates the existing
checkout instead of failing.

Requirements: Omarchy 4 and `python3` (standard library only). Neither the
installer nor the plugin asks for elevated privileges, and it never starts a
second shell process.

## Usage

1. Click the folder icon to open the drawer.
2. Press **＋** to widen it and list the widgets still on your bar.
3. Click one to fold it in.
4. Click a folded row to open that widget's panel, or right-click it to eject it
   back to the bar where it came from.

## How it works

OmaFolder keeps one JSON state file and edits the bar layout for you:

```
~/.config/omafolder/state.json          which widgets are folded, in order
~/.config/omarchy/shell.json            bar.layout.<section> entries
~/.local/state/omafolder/backups/       shell.json backups from every change
```

Folding a widget removes its entry from `bar.layout`, remembering the section
and index; ejecting restores it exactly there. Everything goes through
`bin/omafolder-state`, which prints one JSON object per command and reloads the
shell after a write. Nothing else in `shell.json` is touched.

```sh
bin/omafolder-state summary        # items + metadata
bin/omafolder-state bar-modules    # widgets still on the bar
bin/omafolder-state fold <id>
bin/omafolder-state eject <id>
bin/omafolder-state toggle <id>
bin/omafolder-state reorder <id> <index>
bin/omafolder-state update-check <id>
bin/omafolder-state update <id>
bin/omafolder-state expose <id>     # lend a folded widget to the bar
bin/omafolder-state conceal <id>    # take it back into the folder
bin/omafolder-state eject-all      # used by uninstall.sh
```

Themes are not parsed by hand: colours, radius, fonts and spacing come from the
shell's own `Color` and `Style` singletons, so the drawer follows whatever theme
is active.

Shell IPC (for scripts and shortcuts):

```sh
omarchy-shell shell toggle io.github.shayanshahravi.omafolder '{}'
omarchy-shell shell call io.github.shayanshahravi.omafolder refresh
```

The IPC target is registered once, by the first screen's bar widget, and every
route is relayed to the other monitors' instances, so a call behaves the same on
a multi-monitor setup.

## Move or remove

```sh
omarchy bar move io.github.shayanshahravi.omafolder --section right --index 0
```

```sh
./uninstall.sh            # returns folded widgets to the bar, removes the plugin
./uninstall.sh --purge    # also deletes ~/.config/omafolder
```

## Notes

- Only widgets that are currently on the bar can be folded; the **＋** view lists
  exactly those.
- A folded widget has no live bar instance, so the shell cannot summon its panel
  directly. Clicking such a row returns it to the bar first and opens it there.
- `omarchy.tray` is pinned by the built-in bar. Folding it works, but Omarchy may
  pin it back on the next bar rebuild.
- "Check for update" asks the official Omarchy plugin market for the published
  version and only installs after you confirm in the drawer.

## Development

```sh
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Drawer.qml DrawerItem.qml
python3 -m py_compile bin/omafolder-state

./tests/run.sh          # model logic, QML syntax, state engine
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT © Shayan Shahravi
