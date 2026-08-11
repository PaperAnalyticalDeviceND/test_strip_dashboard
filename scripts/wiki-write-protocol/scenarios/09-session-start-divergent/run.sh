#!/usr/bin/env bash
# Scenario 09: SessionStart on divergent local main.
# B has un-pushed local commits AND origin has commits B doesn't.
# agent_session_start must detect divergence, return 4, and NOT modify
# B's local main (no auto-rebase, no merge).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

noop_resolve() { echo "BUG: scenario 09 should not need a resolver"; exit 1; }

# B's local clone: make a local-only commit (not pushed).
B_WIKI="$(clone_for_agent B)"
cat > "$B_WIKI/B-Local-Work.md" <<'EOF'
# B's Local Work

Committed locally; not pushed.
EOF
git -C "$B_WIKI" add B-Local-Work.md
git -C "$B_WIKI" commit -m "B: local-only work" --quiet
B_LOCAL_SHA=$(git -C "$B_WIKI" rev-parse HEAD)

# A's clone: push a commit to origin (so origin/main moves).
A_WIKI="$(clone_for_agent A)"
cat > "$A_WIKI/A-Pushed-Work.md" <<'EOF'
# A's Pushed Work

Pushed to origin; B has not seen this.
EOF
git -C "$A_WIKI" add A-Pushed-Work.md
git -C "$A_WIKI" commit -m "A: pushed work" --quiet
wiki_push "$A_WIKI" "csweet1" noop_resolve || { echo "FAIL: A push" >&2; exit 1; }

# Now B's local has B-Local-Work; origin has A-Pushed-Work; they share
# the seed but each has a unique commit. Diverged.

echo "Scenario 09: SessionStart on divergent local main"
set +e
ssout=$(agent_session_start "$B_WIKI" 2>&1)
ss_rc=$?
set -e

fail=0
if [ "$ss_rc" -ne 4 ]; then
    echo "FAIL: agent_session_start returned $ss_rc (expected 4 = divergent)"
    fail=$((fail+1))
fi
if ! echo "$ssout" | grep -qE 'DIVERGED'; then
    echo "FAIL: agent_session_start did not report divergence"
    echo "  stdout: $ssout"
    fail=$((fail+1))
fi
# B's local main must NOT have been modified.
B_LOCAL_SHA_AFTER=$(git -C "$B_WIKI" rev-parse HEAD)
if [ "$B_LOCAL_SHA" != "$B_LOCAL_SHA_AFTER" ]; then
    echo "FAIL: B's local main was modified (was $B_LOCAL_SHA, now $B_LOCAL_SHA_AFTER)"
    fail=$((fail+1))
fi
# B's local file should still exist.
if ! [ -f "$B_WIKI/B-Local-Work.md" ]; then
    echo "FAIL: B's local file vanished"
    fail=$((fail+1))
fi
# A's pushed file should NOT yet be in B's local working tree.
if [ -f "$B_WIKI/A-Pushed-Work.md" ]; then
    echo "FAIL: A's file leaked into B's working tree (divergent should defer)"
    fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 09"; exit 0; else echo "FAIL: scenario 09 ($fail)"; exit 1; fi
