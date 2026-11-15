#!/usr/bin/env bash
# OmaFolder installer.
#
# Idempotent: re-running it updates an existing checkout instead of failing,
# and it never touches the bar layout beyond the plugin's own entry.
set -euo pipefail

PLUGIN_ID="io.github.shayanshahravi.omafolder"
REPO_URL="${OMAFOLDER_REPO:-https://github.com/shayanshahravi/OmaFolder}"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omafolder"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omafolder"
SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_INSTALL=0

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
note() { printf '  %s\n' "$1"; }

for argument in "$@"; do
  case "$argument" in
    --local) LOCAL_INSTALL=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: ./install.sh [--local]

  --local   install this checkout instead of cloning the repository
            (for testing uncommitted changes)
USAGE
      exit 0
      ;;
    *) die "unknown option: $argument" ;;
  esac
done

command -v omarchy >/dev/null 2>&1 ||
  die "the omarchy command is required; this plugin installs into Omarchy 4 (Quattro)"
command -v omarchy-shell >/dev/null 2>&1 ||
  die "omarchy-shell is required; start an Omarchy 4 session first"
command -v python3 >/dev/null 2>&1 ||
  die "python3 is required; install it with your package manager and run this again"

printf 'Installing OmaFolder (%s)\n' "$PLUGIN_ID"

# A shell backup before anything can change the layout, so a bad install is a
# copy away from being undone.
if [ -f "$SHELL_JSON" ]; then
  mkdir -p "$STATE_DIR/backups"
  backup="$STATE_DIR/backups/shell.json-$(date +%Y%m%d-%H%M%S).bak"
  cp "$SHELL_JSON" "$backup"
  note "backed up shell.json to $backup"
fi

mkdir -p "$CONFIG_DIR" "$PLUGINS_DIR"

if [ "$LOCAL_INSTALL" -eq 1 ]; then
  if [ -d "$TARGET" ]; then
    retired="$STATE_DIR/backups/$PLUGIN_ID-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$STATE_DIR/backups"
    mv "$TARGET" "$retired"
    note "moved the previous copy to $retired"
  fi
  mkdir -p "$TARGET"
  ( cd "$SOURCE_DIR" && tar -cf - --exclude=.git --exclude=preview.png . ) | tar -xf - -C "$TARGET"
  note "copied $SOURCE_DIR into $TARGET"
elif [ -d "$TARGET/.git" ]; then
  omarchy plugin update "$PLUGIN_ID" --yes
  note "updated the existing checkout"
else
  omarchy plugin add "$REPO_URL" --enable --yes
  note "cloned $REPO_URL"
fi

chmod +x "$TARGET/bin/omafolder-state"
"$TARGET/bin/omafolder-state" init >/dev/null
note "initialised $CONFIG_DIR/state.json"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 || true

# Place the folder on the bar only when it is not there yet: an existing entry
# keeps whatever position the user moved it to.
if ! python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PY'
import json, sys
path, plugin = sys.argv[1], sys.argv[2]
try:
    with open(path) as stream:
        layout = json.load(stream).get("bar", {}).get("layout", {})
except (OSError, ValueError):
    sys.exit(1)
for section in ("left", "center", "right"):
    for entry in layout.get(section) or []:
        if str(entry.get("id") if isinstance(entry, dict) else entry) == plugin:
            sys.exit(0)
sys.exit(1)
PY
then
  omarchy bar move "$PLUGIN_ID" --section left --index 0 >/dev/null 2>&1 ||
    omarchy bar put "$PLUGIN_ID" --section left >/dev/null 2>&1 || true
  note "placed the folder on the left of the bar"
fi

printf 'Done. Click the folder icon to open the drawer.\n'
printf 'Press + to fold a widget, and right-click a row for its actions.\n'
