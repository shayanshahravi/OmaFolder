#!/usr/bin/env bash
# Runs OmaFolder's automated tests.
#
#   tests/run.sh
#
# Qt's qmltestrunner cannot deliver synthetic pointer events on this Qt build, so
# the QML itself is checked for syntax only; every decision it makes lives in
# Model.js or bin/omafolder-state, which are covered here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== JS: model logic"
node --test "$ROOT/tests/model.test.mjs"

echo "== QML: syntax"
for file in BarWidget.qml Drawer.qml DrawerItem.qml; do
  if /usr/lib/qt6/bin/qmllint "$ROOT/$file" 2>&1 | grep -qiE "expected token|syntax error"; then
    echo "syntax error in $file" >&2
    exit 1
  fi
  echo "  $file ok"
done

echo "== Python: state engine"
python3 -m py_compile "$ROOT/bin/omafolder-state"
python3 "$ROOT/tests/engine.test.py"
