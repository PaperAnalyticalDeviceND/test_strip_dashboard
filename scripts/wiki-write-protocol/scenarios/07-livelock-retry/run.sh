#!/usr/bin/env bash
# Scenario 07: livelock / retry cap.
# Pre-receive hook always rejects. With AGENT_MAX_RETRIES=1, the protocol
# does 2 attempts before halting with exit code 2. Local main is left
# with B's commit (un-pushed) for inspection.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

HOOK_DIR="$SANDBOX/origin.git/hooks"
COUNTER="$SANDBOX/.push_counter"
echo 0 > "$COUNTER"
cat > "$HOOK_DIR/pre-receive" <<HOOK
#!/usr/bin/env bash
counter=\$(cat "$COUNTER")
counter=\$((counter + 1))
echo \$counter > "$COUNTER"
echo "Mock reject: simulating persistent livelock (attempt \$counter)" >&2
exit 1
HOOK
chmod +x "$HOOK_DIR/pre-receive"

noop_resolve() {
    echo "BUG: scenario 07 should not need semantic resolution; got $2" >&2
    exit 1
}

apply_B() {
    local wiki="$1"
    cat > "$wiki/Topic-Livelock.md" <<'EOF'
# Topic Livelock

B's write that origin will reject persistently.
EOF
    git -C "$wiki" add Topic-Livelock.md
    git -C "$wiki" commit -m "B: livelock write" --quiet
}

echo "Scenario 07: livelock retry cap"
B_WIKI="$(clone_for_agent B)"
apply_B "$B_WIKI"
AGENT_MAX_RETRIES=1
set +e
wiki_push "$B_WIKI" "vardeman" noop_resolve
rc=$?
set -e

fail=0
if [ "$rc" -ne 2 ]; then
    echo "FAIL: expected exit code 2 (halted at cap); got $rc"
    fail=$((fail+1))
fi
total_pushes=$(cat "$COUNTER")
# AGENT_MAX_RETRIES=1 → 2 total attempts → 2 push attempts (both rejected).
if [ "$total_pushes" -ne 2 ]; then
    echo "FAIL: expected 2 push attempts; got $total_pushes"
    fail=$((fail+1))
fi
# B's local commit should still be present (the wrapper leaves it for inspection).
if ! git -C "$B_WIKI" log --format=%s -1 | grep -qE 'B: livelock write'; then
    echo "FAIL: B's local commit should be preserved for inspection"
    fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 07"; exit 0; else echo "FAIL: scenario 07 ($fail)"; exit 1; fi
