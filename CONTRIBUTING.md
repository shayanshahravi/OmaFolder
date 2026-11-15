# Contributing

Thanks for wanting to improve OmaFolder.

## Layout

```
manifest.json      plugin contract (bar-widget, BarWidget.qml)
BarWidget.qml      bar entry point: folder icon, badge, panel forwarding
Drawer.qml         the drawer: panel lifecycle, state, drag & drop, manage view
DrawerItem.qml     one row: icon, hold ring, tooltip, drag source and drop target
Model.js           pure helpers (icons, labels, ordering) — no QML types
bin/omafolder-state  state engine: state.json + shell.json, JSON on stdout
install.sh / uninstall.sh
```

Everything that mutates state belongs in `bin/omafolder-state`; the QML should
render and call it, not edit `shell.json` itself. That keeps the drawer, the bar
and a shell restart in agreement.

## Before opening a pull request

```sh
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Drawer.qml DrawerItem.qml
python3 -m py_compile bin/omafolder-state
shellcheck install.sh uninstall.sh

./tests/run.sh          # model logic, QML syntax, state engine
./tests/run.sh --live   # also drives drag and drop inside the running shell
```

Drag and drop has to be tested with drags, not clicks: `tests/run.sh --live`
patches the installed copy with a short harness that calls the drawer's real
`drag()` path from inside the shell, restarts the shell, checks the resulting
order and bar layout, then reinstalls the clean copy. It restarts the shell
twice, so run it deliberately.

Test by hand, since the plugin only exists inside a running shell:

1. `./install.sh --local`
2. `omarchy-shell shell rescanPlugins`
3. `omarchy-shell shell toggle io.github.shayanshahravi.omafolder '{}'`
4. Fold a widget, click it, hold it for three seconds, drag it out, and reopen
   the drawer after a shell restart (`omarchy-restart-shell`).
5. `cat ~/.config/omafolder/state.json` and
   `python3 -c "import json;print(json.load(open('$HOME/.config/omarchy/shell.json'))['bar']['layout'])"`
   to confirm the bar layout matches what you see.

Please keep behaviour changes small and described in `CHANGELOG.md`. Do not add
dependencies beyond `python3`'s standard library without discussion first.

## Never commit

- `~/.config/omarchy/shell.json` or any personal state file
- tokens, secrets or personal screenshots of your desktop
