#!/usr/bin/env bash
# Scenario 06: push race. Pre-receive hook on origin rejects exactly the
# 2nd push attempt (which is B's first push). The wrapper detects, fetches,
# merges (clean: different files) and retries. Verifies 3 push attempts
# total (A=1, B=2 attempts including the rejected one).

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
if [ "\$counter" -eq 2 ]; then
    echo "Mock reject: simulating push race on attempt \$counter" >&2
    exit 1
fi
exit 0
HOOK
chmod +x "$HOOK_DIR/pre-receive"

noop_resolve() {
    echo "BUG: scenario 06 should not need semantic resolution; got $2" >&2
    exit 1
}

apply_A() {
    local wiki="$1"
    cat > "$wiki/Topic-Race-A.md" <<'EOF'
# Topic Race A

Authored by A in the race scenario.
EOF
    git -C "$wiki" add Topic-Race-A.md
    git -C "$wiki" commit -m "A: race write" --quiet
}

apply_B() {
    local wiki="$1"
    cat > "$wiki/Topic-Race-B.md" <<'EOF'
# Topic Race B

Authored by B in the race scenario.
EOF
    git -C "$wiki" add Topic-Race-B.md
    git -C "$wiki" commit -m "B: race write" --quiet
}

echo "Scenario 06: push race"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
apply_A "$A_WIKI"
apply_B "$B_WIKI"
wiki_push "$A_WIKI" "csweet1"  noop_resolve || { echo "FAIL: A push" >&2; exit 1; }
wiki_push "$B_WIKI" "vardeman" noop_resolve || { echo "FAIL: B push" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
[ -f "$VERIFY/Topic-Race-A.md" ] || { echo "FAIL: A's page missing"; fail=$((fail+1)); }
[ -f "$VERIFY/Topic-Race-B.md" ] || { echo "FAIL: B's page missing"; fail=$((fail+1)); }
total_pushes=$(cat "$COUNTER")
if [ "$total_pushes" -ne 3 ]; then
    echo "FAIL: expected 3 push attempts (A + B initial + B retry); got $total_pushes"
    fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 06"; exit 0; else echo "FAIL: scenario 06 ($fail)"; exit 1; fi
