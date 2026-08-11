#!/usr/bin/env bash
# Scenario 02: two agents edit different sections of the same page.
# Three-way merge handles it without semantic resolution.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

# Seed Welcome.md with multiple sections.
git -C "$SANDBOX/main" pull --quiet
cat > "$SANDBOX/main/Welcome.md" <<'EOF'
# Welcome

Intro paragraph.

## Method

(method placeholder)

## Results

(results placeholder)

## Discussion

(discussion placeholder)
EOF
git -C "$SANDBOX/main" add Welcome.md
git -C "$SANDBOX/main" commit -m "Seed Welcome with sections" --quiet
git -C "$SANDBOX/main" push --quiet

noop_resolve() {
    echo "BUG: scenario 02 should not need semantic resolution; got $2" >&2
    cat "$1/$2" >&2
    exit 1
}

apply_A() {
    local wiki="$1"
    awk '
        /^## Method/ { print; print ""; print "Method by agent A: derived from first-principles."; in_m=1; next }
        /^## / && in_m { in_m=0 }
        in_m && /^\(method placeholder\)$/ { next }
        { print }
    ' "$wiki/Welcome.md" > "$wiki/Welcome.md.new"
    mv "$wiki/Welcome.md.new" "$wiki/Welcome.md"
    git -C "$wiki" add Welcome.md
    git -C "$wiki" commit -m "A: edit Method" --quiet
}

apply_B() {
    local wiki="$1"
    awk '
        /^## Results/ { print; print ""; print "Results by agent B: measured on test corpus."; in_r=1; next }
        /^## / && in_r { in_r=0 }
        in_r && /^\(results placeholder\)$/ { next }
        { print }
    ' "$wiki/Welcome.md" > "$wiki/Welcome.md.new"
    mv "$wiki/Welcome.md.new" "$wiki/Welcome.md"
    git -C "$wiki" add Welcome.md
    git -C "$wiki" commit -m "B: edit Results" --quiet
}

echo "Scenario 02: different sections of same page"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
apply_A "$A_WIKI"
apply_B "$B_WIKI"
wiki_push "$A_WIKI" "csweet1"  noop_resolve || { echo "FAIL: A push" >&2; exit 1; }
wiki_push "$B_WIKI" "vardeman" noop_resolve || { echo "FAIL: B push" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
grep -qE 'Method by agent A'  "$VERIFY/Welcome.md" || { echo "FAIL: Method section lacks A's edit";  fail=$((fail+1)); }
grep -qE 'Results by agent B' "$VERIFY/Welcome.md" || { echo "FAIL: Results section lacks B's edit"; fail=$((fail+1)); }
grep -qE 'Discussion'         "$VERIFY/Welcome.md" || { echo "FAIL: Discussion section gone";        fail=$((fail+1)); }
if grep -qE '<<<<<<<|>>>>>>>' "$VERIFY/Welcome.md"; then
    echo "FAIL: conflict markers leaked"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 02"; exit 0; else echo "FAIL: scenario 02 ($fail)"; exit 1; fi
