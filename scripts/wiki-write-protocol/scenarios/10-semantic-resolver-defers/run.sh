#!/usr/bin/env bash
# Scenario 10: the semantic resolver FAILS (the documented production
# llm_resolve, which defers to the agent's next turn). Contract under test
# (#94, field-reported on naval-sensor-fusion): a failing resolve must
# leave the merge in its conflicted state and return non-zero — nothing
# containing conflict markers may ever reach origin. The recovery leg then
# exercises the documented flow: hand-resolve, commit, re-run wiki_push.
#
# Anatomy mirrors the field event: A lands a new page + index/log entries
# + an edit to OSPA-Metric.md; B holds different index/log entries + an
# edit to the SAME paragraph.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

git -C "$SANDBOX/main" pull --quiet
cat > "$SANDBOX/main/OSPA-Metric.md" <<'EOF'
# OSPA Metric

## Role in the project

(placeholder paragraph)
EOF
printf '# Index\n\n- [OSPA-Metric](OSPA-Metric)\n' > "$SANDBOX/main/index_wiki.md"
printf '# Log\n\n## [2026-07-01] seed\n' > "$SANDBOX/main/log_wiki.md"
git -C "$SANDBOX/main" add -A
git -C "$SANDBOX/main" commit -m "Seed OSPA + index + log" --quiet
git -C "$SANDBOX/main" push --quiet

apply_A() {
    local wiki="$1"
    printf '# JADC2\n\nNew page from collaborator A.\n' > "$wiki/JADC2.md"
    printf -- '- [JADC2](JADC2)\n' >> "$wiki/index_wiki.md"
    printf '\n## [2026-07-20] ingest | JADC2 by A\n' >> "$wiki/log_wiki.md"
    cat > "$wiki/OSPA-Metric.md" <<'EOF'
# OSPA Metric

## Role in the project

Grounds the benchmarking-and-down-select methodology.
EOF
    git -C "$wiki" add -A
    git -C "$wiki" commit -m "A: JADC2 + OSPA edit" --quiet
}

apply_B() {
    local wiki="$1"
    printf '\n## [2026-07-20] milestone | Layer-4 runner by B\n' >> "$wiki/log_wiki.md"
    printf -- '- [Milestones](Milestones)\n' >> "$wiki/index_wiki.md"
    cat > "$wiki/OSPA-Metric.md" <<'EOF'
# OSPA Metric

## Role in the project

Scored by the Layer-4 experiment runner.
EOF
    git -C "$wiki" add -A
    git -C "$wiki" commit -m "B: milestone + OSPA edit" --quiet
}

noop() { echo "BUG: A should not hit resolver"; exit 1; }
# The DOCUMENTED production resolver (wiki/agents/wiki-write-protocol.md):
# defer to the agent turn, leave the markers in place.
llm_resolve() { return 1; }

echo "Scenario 10: semantic resolver defers (returns 1)"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
apply_A "$A_WIKI"
apply_B "$B_WIKI"
wiki_push "$A_WIKI" "collabA" noop || { echo "FAIL: A push" >&2; exit 1; }

set +e
wiki_push "$B_WIKI" "reporter" llm_resolve
B_RC=$?
set -e

fail=0
# 1. The deferred resolve must surface as non-zero (contract: exit 4).
[ "$B_RC" -eq 4 ] || { echo "FAIL: wiki_push returned $B_RC, expected 4 (deferred)"; fail=$((fail+1)); }

# 2. NOTHING with conflict markers on origin — the core of the field bug.
VERIFY="$(clone_for_agent verify1)"
if grep -rqE '^(<<<<<<< |>>>>>>> )' "$VERIFY" --include='*.md' 2>/dev/null; then
    echo "FAIL: conflict markers reached origin"; fail=$((fail+1))
fi
# 3. B's deferred edit must NOT be on origin yet.
if grep -q 'Layer-4 experiment runner' "$VERIFY/OSPA-Metric.md" 2>/dev/null; then
    echo "FAIL: B's unresolved edit leaked to origin"; fail=$((fail+1))
fi

# 4. B's working tree left in conflicted state, markers in place for the agent.
git -C "$B_WIKI" diff --name-only --diff-filter=U | grep -q 'OSPA-Metric.md' \
    || { echo "FAIL: OSPA-Metric.md not left in conflicted state"; fail=$((fail+1)); }
grep -qE '^<<<<<<< ' "$B_WIKI/OSPA-Metric.md" \
    || { echo "FAIL: markers not present locally for the agent to resolve"; fail=$((fail+1)); }

# 5. Recovery: the documented flow — agent resolves in place (both sides
#    kept, like the field fix), commits the merge, re-runs wiki_push.
cat > "$B_WIKI/OSPA-Metric.md" <<'EOF'
# OSPA Metric

## Role in the project

Grounds the benchmarking-and-down-select methodology.
Scored by the Layer-4 experiment runner.
EOF
git -C "$B_WIKI" add OSPA-Metric.md
git -C "$B_WIKI" commit -m "Resolve OSPA collision (both sides kept)" --quiet
wiki_push "$B_WIKI" "reporter" llm_resolve || { echo "FAIL: recovery push"; fail=$((fail+1)); }

VERIFY2="$(clone_for_agent verify2)"
grep -q 'benchmarking-and-down-select' "$VERIFY2/OSPA-Metric.md" || { echo "FAIL: A's sentence missing after recovery"; fail=$((fail+1)); }
grep -q 'Layer-4 experiment runner'    "$VERIFY2/OSPA-Metric.md" || { echo "FAIL: B's sentence missing after recovery"; fail=$((fail+1)); }
grep -q 'JADC2 by A'                   "$VERIFY2/log_wiki.md"    || { echo "FAIL: A's log entry missing (union)"; fail=$((fail+1)); }
grep -q 'Layer-4 runner by B'          "$VERIFY2/log_wiki.md"    || { echo "FAIL: B's log entry missing (union)"; fail=$((fail+1)); }
if grep -rqE '^(<<<<<<< |>>>>>>> )' "$VERIFY2" --include='*.md' 2>/dev/null; then
    echo "FAIL: markers on origin after recovery"; fail=$((fail+1))
fi

if [ "$fail" -gt 0 ]; then echo "Scenario 10: $fail failure(s)"; exit 1; fi
echo "Scenario 10: PASS"
