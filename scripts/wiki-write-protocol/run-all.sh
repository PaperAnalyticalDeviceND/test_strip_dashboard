#!/usr/bin/env bash
# Run every scenario; report PASS/FAIL count. Exit code = number of failures.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

PASS=0
FAIL=0
FAILED=()

for scenario in "$HERE"/scenarios/*/run.sh; do
    name="$(basename "$(dirname "$scenario")")"
    echo "================================================================"
    echo "Running $name"
    echo "================================================================"
    if bash "$scenario"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED+=("$name")
    fi
    echo ""
done

echo "================================================================"
echo "Summary: $PASS passed, $FAIL failed"
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Failures:"
    for f in "${FAILED[@]}"; do echo "  - $f"; done
fi
exit "$FAIL"
