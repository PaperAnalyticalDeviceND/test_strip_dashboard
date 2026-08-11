#!/usr/bin/env bash
# Patch: fixture for manifest sync-trees (issue #90).
#
# Field case: scripts/test/ ships at instantiation but was absent from the
# manifest, so derived repos ran a harness frozen at creation vintage —
# red CI for days on naval-sensor-fusion (pre-#73 fixtures against a
# derived tree). The fix declares scripts/test as a SYNC TREE whose
# membership is resolved from the sync source at run time.
#
# Effects: creates $SANDBOX/harness-tree-sync/ with:
#   template-src/  stand-in template repo (branch main): a minimal harness
#                  tree (run.sh, lib/, one fixture), the CI workflow file,
#                  and one SHARED_INFRA control file
#   host/          derived project with CURRENT sync tooling (copied from
#                  the working tree under test), a STALE harness runner,
#                  and a host-owned feature test that the sync must never
#                  touch (copy-no-delete contract)
#   adopt-host/    virgin repo for the adopt leg (dir-mode enumeration)
#
# Hermetic: remotes are local paths.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/harness-tree-sync"
mkdir -p "$STAGE"
g() { git "$@"; }

# --- template-src ---
T="$STAGE/template-src"
g init -q "$T"
g -C "$T" symbolic-ref HEAD refs/heads/main
mkdir -p "$T/scripts/test/lib" "$T/scripts/test/tests/unit/sample" "$T/.github/workflows"
printf '#!/usr/bin/env bash\n# NEW-RUNNER-MARKER (post-guard harness)\n' > "$T/scripts/test/run.sh"
printf '# guard lib shipped by template\n'                               > "$T/scripts/test/lib/guard.sh"
printf '# sample fixture assertions\n'       > "$T/scripts/test/tests/unit/sample/assertions.sh"
printf 'name: test-harness\non: [push]\n'    > "$T/.github/workflows/test-harness.yml"
printf 'control shared file\n'               > "$T/llm-wiki.md"
g -C "$T" add -A
g -C "$T" commit -q -m "template content"

# --- host: current tooling + stale harness + host-owned feature test ---
H="$STAGE/host"
g init -q "$H"
mkdir -p "$H/wiki/hosty.wiki" "$H/scripts/lib" \
         "$H/scripts/test/tests/unit/myfeat"
: > "$H/wiki/hosty.wiki/SCHEMA_hosty.md"
cp "$TEMPLATE_ROOT/scripts/update-from-template.sh"   "$H/scripts/"
cp "$TEMPLATE_ROOT/scripts/check-template-version.sh" "$H/scripts/"
cp "$TEMPLATE_ROOT"/scripts/lib/*.sh                  "$H/scripts/lib/"
printf '#!/usr/bin/env bash\n# OLD-RUNNER-MARKER (pre-guard, fails in derived checkouts)\n' \
    > "$H/scripts/test/run.sh"
printf '# HOST-FEATURE-TEST-MARKER: installed by a feature; sync must never touch this\n' \
    > "$H/scripts/test/tests/unit/myfeat/assertions.sh"

# --- adopt leg: virgin host, adopted from the REAL template working tree ---
A="$STAGE/adopt-host"
g init -q "$A"
g -C "$A" remote add origin "https://github.com/example-org/adopt-host.git"
printf '# Adopt Host\n' > "$A/README.md"
g -C "$A" add -A
g -C "$A" commit -q -m "host baseline"

echo "  harness-tree-sync patch applied: fixtures at $STAGE"
