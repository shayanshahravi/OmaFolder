#!/usr/bin/env bash
# Runs OmaFolder's automated tests.
#
#   tests/run.sh            unit tests only
#   tests/run.sh --live     also drives a real drag inside the running shell
#
# The drag gesture itself is verified against the live shell through the
# plugin's `drag` IPC method (see tests/live-drag.sh). Qt's qmltestrunner cannot
# deliver synthetic pointer events on this Qt build, so a standalone gesture
# suite would report false failures.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== JS: model logic"
node --test "$ROOT/tests/model.test.mjs"

echo "== QML: syntax"
QML="$(command -v qmlformat >/dev/null 2>&1 && echo ok || true)"
for file in BarWidget.qml Drawer.qml DrawerItem.qml; do
  /usr/lib/qt6/bin/qmllint "$ROOT/$file" 2>&1 | grep -qiE "expected token|syntax error" && {
    echo "syntax error in $file" >&2
    exit 1
  }
  echo "  $file ok"
done

echo "== Python: state engine"
python3 -m py_compile "$ROOT/bin/omafolder-state"
echo "  omafolder-state ok"

if [ "${1:-}" = "--live" ]; then
  echo "== Live: drag inside the running shell"
  "$ROOT/tests/live-drag.sh"
fi
