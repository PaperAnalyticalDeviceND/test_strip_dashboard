#!/usr/bin/env bash
# Scenario 01: two agents add different new pages.
# A commits + pushes (clean). B commits + pushes; B's push is rejected
# because origin has moved; wiki_push fetches and merges (clean: different
# files, plus union-merge for index/log) and retries successfully.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

noop_resolve() {
    echo "BUG: scenario 01 should not need semantic resolution; got $2" >&2
    exit 1
}

apply_A() {
    local wiki="$1"
    cat > "$wiki/Topic-Alpha.md" <<'EOF'
# Topic Alpha

Authored by agent A (csweet1).
EOF
    echo "- [Topic-Alpha](Topic-Alpha)" >> "$wiki/index_proto.md"
    echo "" >> "$wiki/log_proto.md"
    echo "## [2026-05-31] ingest | A added Topic-Alpha" >> "$wiki/log_proto.md"
    git -C "$wiki" add Topic-Alpha.md index_proto.md log_proto.md
    git -C "$wiki" commit -m "A: add Topic-Alpha" --quiet
}

apply_B() {
    local wiki="$1"
    cat > "$wiki/Topic-Beta.md" <<'EOF'
# Topic Beta

Authored by agent B (vardeman).
EOF
    echo "- [Topic-Beta](Topic-Beta)" >> "$wiki/index_proto.md"
    echo "" >> "$wiki/log_proto.md"
    echo "## [2026-05-31] ingest | B added Topic-Beta" >> "$wiki/log_proto.md"
    git -C "$wiki" add Topic-Beta.md index_proto.md log_proto.md
    git -C "$wiki" commit -m "B: add Topic-Beta" --quiet
}

echo "Scenario 01: different pages"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
apply_A "$A_WIKI"
apply_B "$B_WIKI"
wiki_push "$A_WIKI" "csweet1"  noop_resolve || { echo "FAIL: A push" >&2; exit 1; }
wiki_push "$B_WIKI" "vardeman" noop_resolve || { echo "FAIL: B push" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
[ -f "$VERIFY/Topic-Alpha.md" ] || { echo "FAIL: Topic-Alpha.md missing"; fail=$((fail+1)); }
[ -f "$VERIFY/Topic-Beta.md" ]  || { echo "FAIL: Topic-Beta.md missing";  fail=$((fail+1)); }
grep -qE 'Topic-Alpha' "$VERIFY/index_proto.md" || { echo "FAIL: index lacks Topic-Alpha"; fail=$((fail+1)); }
grep -qE 'Topic-Beta'  "$VERIFY/index_proto.md" || { echo "FAIL: index lacks Topic-Beta";  fail=$((fail+1)); }
grep -qE 'A added Topic-Alpha' "$VERIFY/log_proto.md" || { echo "FAIL: log lacks A entry"; fail=$((fail+1)); }
grep -qE 'B added Topic-Beta'  "$VERIFY/log_proto.md" || { echo "FAIL: log lacks B entry"; fail=$((fail+1)); }

if [ $fail -eq 0 ]; then echo "PASS: scenario 01"; exit 0; else echo "FAIL: scenario 01 ($fail)"; exit 1; fi
