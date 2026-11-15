#!/usr/bin/env bash
# End-to-end drag test inside the running Omarchy shell.
#
#   tests/live-drag.sh
#
# Qt's qmltestrunner cannot deliver synthetic pointer events on this Qt build,
# and a plugin's IpcHandler is not reachable from `omarchy-shell shell call`, so
# this drives the drawer from inside the shell instead: it patches the installed
# copy with a short timer that calls the drawer's real drag() entry point (begin
# -> move -> hit test -> drop rule -> state write), restarts the shell, reads the
# log it leaves behind, and then reinstalls the clean copy.
#
# It restarts the shell twice and temporarily edits the installed plugin, so run
# it deliberately, not on every save. It needs at least two folded widgets.
set -euo pipefail

PLUGIN_ID="io.github.shayanshahravi.omafolder"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
DRAWER="$PLUGIN_DIR/Drawer.qml"
STATE="${XDG_CONFIG_HOME:-$HOME/.config}/omafolder/state.json"
SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
LOG=/tmp/omafolder-selftest.log
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

[ -f "$DRAWER" ] || { echo "OmaFolder is not installed at $PLUGIN_DIR" >&2; exit 1; }

items_json() { python3 -c "import json;print(','.join(i['id'] for i in json.load(open('$STATE'))['items']))"; }
bar_has() { python3 -c "import json,sys;d=json.load(open('$SHELL_JSON'));print(any(e.get('id')==sys.argv[1] for s in ('left','center','right') for e in d['bar']['layout'][s]))" "$1"; }

before="$(items_json)"
count=$(python3 -c "print(len([i for i in open('$STATE').read().split('\"id\"')[1:]]))" 2>/dev/null || echo 0)
if [ "$(echo "$before" | tr ',' '\n' | grep -c .)" -lt 2 ]; then
  echo "need at least two folded widgets to test dragging, found: $before" >&2
  exit 1
fi

echo "== installing the in-shell harness"
cp "$DRAWER" "$DRAWER.pre-test"
python3 - "$DRAWER" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
block = '''
  // ---- test harness injected by tests/live-drag.sh ----
  property int selfTestStep: 0
  Process { id: stLog; command: ["/bin/sh", "-c", "true"] }
  function stLogLine(message) {
    stLog.command = ["/bin/sh", "-c", "printf '%s\\\\n' " + String.fromCharCode(34) + message + String.fromCharCode(34) + " >> /tmp/omafolder-selftest.log"]
    stLog.running = true
  }
  function stIds() { return root.items.map(function(i) { return i.id }).join(",") }
  Process {
    id: claim
    command: ["/bin/sh", "-c", "mkdir /tmp/omafolder-selftest.claim 2>/dev/null && echo go || echo skip"]
    stdout: StdioCollector { id: claimOut; waitForEnd: true }
    onExited: function() {
      if (String(claimOut.text).indexOf("go") !== 0) root.selfTestStep = 99
    }
  }
  Timer {
    interval: 1300
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      var step = root.selfTestStep
      if (step === 0) {
        root.open()
        stLogLine("opened")
        // The drawer exists once per bar surface; only the instance that wins
        // the claim file runs the steps, so one test ejects one widget.
        claim.running = true
      }
      else if (step === 1) stLogLine("before=" + stIds())
      else if (step === 2) stLogLine("dragA=" + drag(0, "2"))
      else if (step === 3) stLogLine("afterA=" + stIds())
      else if (step === 4) stLogLine("dragB=" + drag(2, "0"))
      else if (step === 5) stLogLine("afterB=" + stIds())
      else if (step === 6) stLogLine("dragOut=" + drag(root.items.length - 1, "out"))
      else if (step === 7) { stLogLine("afterOut=" + stIds()); stLogLine("done") }
      root.selfTestStep = step + 1
      if (step >= 7) running = false
    }
  }
'''
idx = src.rstrip().rfind("\n}")
open(path, "w").write(src[:idx] + "\n" + block + src[idx:])
PY

restore() {
  if [ -f "$DRAWER.pre-test" ]; then
    mv "$DRAWER.pre-test" "$DRAWER"
  fi
}
trap restore EXIT

rm -rf "$LOG" /tmp/omafolder-selftest.claim
echo "== restarting the shell to run the harness (first restart)"
timeout 60 omarchy-restart-shell >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
  grep -q "done" "$LOG" 2>/dev/null && break
  sleep 1
done

if ! [ -f "$LOG" ]; then
  echo "the harness produced no log; is omarchy-shell running?" >&2
  exit 1
fi

logged_before="$(sed -n 's/^before=//p' "$LOG" | tail -1)"
after_a="$(sed -n 's/^afterA=//p' "$LOG" | tail -1)"
after_b="$(sed -n 's/^afterB=//p' "$LOG" | tail -1)"
after_out="$(sed -n 's/^afterOut=//p' "$LOG" | tail -1)"
drag_a="$(sed -n 's/^dragA=//p' "$LOG" | tail -1)"
drag_out="$(sed -n 's/^dragOut=//p' "$LOG" | tail -1)"

echo "== reorder: row 0 onto row 2"
expected_a="$(python3 -c "
ids='$logged_before'.split(',')
ids.insert(2, ids.pop(0))
print(','.join(ids))")"
if [ -n "$after_a" ] && [ "$after_a" = "$expected_a" ]; then
  pass "order follows the drop ($drag_a)"
else
  fail "order did not follow the drop: $drag_a
    before:   $logged_before
    after:    $after_a
    expected: $expected_a"
fi

echo "== reorder back"
if [ -n "$after_b" ] && [ "$after_b" = "$logged_before" ]; then
  pass "order restored"
else
  fail "order was not restored: $after_b"
fi

echo "== drag out of the drawer"
ejected="${logged_before##*,}"
if echo "$after_out" | tr ',' '\n' | grep -qxF "$ejected"; then
  fail "$ejected is still in the drawer after dragging out: $drag_out"
elif [ "$(bar_has "$ejected")" = "True" ]; then
  pass "$ejected left the drawer and is back on the bar"
else
  fail "$ejected is neither folded nor on the bar: $drag_out"
fi

echo "== restoring the widget the test ejected"
if ! items_json | tr ',' '\n' | grep -qxF "$ejected"; then
  # It was the last row, so folding it again puts it back where it was.
  "$PLUGIN_DIR/bin/omafolder-state" fold "$ejected" >/dev/null 2>&1 || true
fi

if echo "$(items_json)" | tr ',' '\n' | grep -qxF "$ejected"; then
  pass "$ejected is folded again"
else
  fail "could not fold $ejected back"
fi

echo "== reinstalling the clean copy (second restart)"
"$ROOT/install.sh" --local >/dev/null 2>&1
timeout 60 omarchy-restart-shell >/dev/null 2>&1 || true

if [ "$fails" -ne 0 ]; then
  printf '%s drag check(s) failed\n' "$fails" >&2
  exit 1
fi
echo "all drag checks passed"
