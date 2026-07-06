#!/usr/bin/env bash
# Runs the whole headless test suite. Execute from the screw_puzzle/ folder:
#   ./tests/run_all.sh
# Override the Godot binary with:  GODOT=/path/to/godot ./tests/run_all.sh
set -u
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

for test in test_blocking test_level_data test_detach; do
    echo ""
    echo "--- $test ---"
    "$GODOT" --headless --path "$DIR" --script "res://tests/$test.gd"
    if [ $? -ne 0 ]; then
        FAILED=1
    fi
done

echo ""
if [ $FAILED -eq 0 ]; then
    echo "=== ALL TEST SCRIPTS PASSED ==="
else
    echo "=== SOME TEST SCRIPTS FAILED ==="
fi
exit $FAILED
