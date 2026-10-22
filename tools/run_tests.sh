#!/bin/bash
# Runs the headless test suite. Usage: tools/run_tests.sh [path-to-godot]
# Godot prints script errors to its log; --log-file keeps them visible even when stdout is piped.
set -u
GODOT=${1:-godot}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOG=$(mktemp)
run() {
  timeout "$1" "$GODOT" --path "$ROOT" --headless --log-file "$LOG" "${@:2}" < /dev/null > /dev/null 2>&1
  grep -vE "^Godot Engine|^$|ObjectDB instances leaked|resources still in use|at: (cleanup|clear) " "$LOG"
}
echo "== import"; run 300 --import > /dev/null
echo "== compile check"; run 120 --script res://scripts/tests/check.gd
echo "== mechanics"; run 300 --script res://scripts/tests/scenarios.gd
echo "== 20-minute AI vs AI game + save/load"; run 900 --script res://scripts/tests/autotest.gd -- 1 20 2 lakes normal
rm -f "$LOG"
