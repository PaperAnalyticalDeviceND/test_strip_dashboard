#!/usr/bin/env bash
# Scenario 04: two agents both append new index entries.
# Union merge driver (.gitattributes) handles automatically; no resolver.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

noop_resolve() {
    echo "BUG: scenario 04 should not need semantic resolution; got $2" >&2
    cat "$1/$2" >&2
    exit 1
}

apply_A() {
    local wiki="$1"
    echo "- [Topic-A-Index](Topic-A-Index): added by agent A" >> "$wiki/index_proto.md"
    git -C "$wiki" add index_proto.md
    git -C "$wiki" commit -m "A: index entry" --quiet
}

apply_B() {
    local wiki="$1"
    echo "- [Topic-B-Index](Topic-B-Index): added by agent B" >> "$wiki/index_proto.md"
    git -C "$wiki" add index_proto.md
    git -C "$wiki" commit -m "B: index entry" --quiet
}

echo "Scenario 04: index union merge"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
apply_A "$A_WIKI"
apply_B "$B_WIKI"
wiki_push "$A_WIKI" "csweet1"  noop_resolve || { echo "FAIL: A push" >&2; exit 1; }
wiki_push "$B_WIKI" "vardeman" noop_resolve || { echo "FAIL: B push" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
grep -qE 'Topic-A-Index' "$VERIFY/index_proto.md" || { echo "FAIL: A index entry missing"; fail=$((fail+1)); }
grep -qE 'Topic-B-Index' "$VERIFY/index_proto.md" || { echo "FAIL: B index entry missing"; fail=$((fail+1)); }
if grep -qE '<<<<<<<|>>>>>>>' "$VERIFY/index_proto.md"; then
    echo "FAIL: conflict markers leaked into index"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 04"; exit 0; else echo "FAIL: scenario 04 ($fail)"; exit 1; fi
