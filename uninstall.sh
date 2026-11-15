#!/usr/bin/env bash
# OmaFolder uninstaller.
#
# Puts every folded widget back on the bar before removing the plugin, so
# uninstalling never leaves widgets stranded inside a folder that no longer
# exists.
set -euo pipefail

PLUGIN_ID="io.github.shayanshahravi.omafolder"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omafolder"
PURGE=0

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
note() { printf '  %s\n' "$1"; }

for argument in "$@"; do
  case "$argument" in
    --purge) PURGE=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: ./uninstall.sh [--purge]

  --purge   also delete ~/.config/omafolder (state file and settings)
USAGE
      exit 0
      ;;
    *) die "unknown option: $argument" ;;
  esac
done

engine="$TARGET/bin/omafolder-state"
if [ -x "$engine" ]; then
  printf 'Returning folded widgets to the bar\n'
  "$engine" eject-all >/dev/null || note "nothing to return"
fi

if [ -d "$TARGET" ]; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  omarchy plugin remove "$PLUGIN_ID" --yes >/dev/null 2>&1 || rm -rf "$TARGET"
  note "removed $TARGET"
fi

if [ "$PURGE" -eq 1 ] && [ -d "$CONFIG_DIR" ]; then
  rm -rf "$CONFIG_DIR"
  note "removed $CONFIG_DIR"
fi

printf 'Done. Restart the shell if the folder icon is still on the bar.\n'
