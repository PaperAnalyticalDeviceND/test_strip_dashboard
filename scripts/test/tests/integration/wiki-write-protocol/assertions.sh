# Integration test: drives the wiki write-protocol scenarios from the
# harness. Each scenario is reported as a single harness assertion. The
# reference implementation lives independently at
# scripts/wiki-write-protocol/ and remains runnable standalone via that
# directory's run-all.sh.
#
# Each scenario manages its own sandbox (via the implementation's
# sandbox.sh), so the harness's $SANDBOX is not used here.

PROTO_DIR="$(cd "$HERE/../wiki-write-protocol" && pwd)"

if [ ! -d "$PROTO_DIR/scenarios" ]; then
    echo "  protocol prototype not found at $PROTO_DIR; skipping"
    skip "wiki-write-protocol: prototype directory missing" "$PROTO_DIR not found"
    return
fi

for scenario_script in "$PROTO_DIR"/scenarios/*/run.sh; do
    name=$(basename "$(dirname "$scenario_script")")
    log="/tmp/wiki-write-protocol-${name}.log"
    if bash "$scenario_script" > "$log" 2>&1; then
        assert "wiki-write-protocol/$name" "true"
    else
        echo "    (scenario log at $log; last 10 lines below)"
        tail -10 "$log" 2>/dev/null | sed 's/^/    /'
        assert "wiki-write-protocol/$name" "false"
    fi
done
