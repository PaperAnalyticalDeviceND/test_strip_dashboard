#!/usr/bin/env bash
# Scenario 08: SessionStart auto-pull.
# A pushes a commit. B's agent_session_start fast-forwards local main
# to include A's commit. B can now read what A wrote without manual
# fetching.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

noop_resolve() { echo "BUG: scenario 08 should not need a resolver"; exit 1; }

apply_A() {
    local wiki="$1"
    cat > "$wiki/Topic-A-Session.md" <<'EOF'
# Topic A Session

Written by A; B should see this after SessionStart.
EOF
    git -C "$wiki" add Topic-A-Session.md
    git -C "$wiki" commit -m "A: write Topic-A-Session" --quiet
}

echo "Scenario 08: SessionStart auto-pull"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"

# A makes its change and pushes.
apply_A "$A_WIKI"
wiki_push "$A_WIKI" "csweet1" noop_resolve || { echo "FAIL: A push" >&2; exit 1; }

# Before SessionStart, B's local clone does NOT have A's file.
if [ -f "$B_WIKI/Topic-A-Session.md" ]; then
    echo "FAIL: B should not yet have A's file"; exit 1
fi

# B runs agent_session_start. Should fast-forward and report A's commit.
set +e
ssout=$(agent_session_start "$B_WIKI" 2>&1)
ss_rc=$?
set -e

fail=0
if [ "$ss_rc" -ne 0 ]; then
    echo "FAIL: agent_session_start returned $ss_rc (expected 0)"
    fail=$((fail+1))
fi
if ! [ -f "$B_WIKI/Topic-A-Session.md" ]; then
    echo "FAIL: B's local main did not fast-forward to include A's file"
    fail=$((fail+1))
fi
if ! echo "$ssout" | grep -qE 'pulled [0-9]+ incoming commit'; then
    echo "FAIL: agent_session_start did not report incoming commits"
    echo "  stdout: $ssout"
    fail=$((fail+1))
fi
if ! echo "$ssout" | grep -qE 'write Topic-A-Session'; then
    echo "FAIL: agent_session_start did not surface the commit subject"
    echo "  stdout: $ssout"
    fail=$((fail+1))
fi

# Idempotence: running it again should report "up to date".
set +e
ssout2=$(agent_session_start "$B_WIKI" 2>&1)
ss_rc2=$?
set -e
if [ "$ss_rc2" -ne 0 ]; then
    echo "FAIL: second session_start returned $ss_rc2"
    fail=$((fail+1))
fi
if ! echo "$ssout2" | grep -qE 'up to date'; then
    echo "FAIL: second session_start did not report up-to-date"
    echo "  stdout: $ssout2"
    fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 08"; exit 0; else echo "FAIL: scenario 08 ($fail)"; exit 1; fi
