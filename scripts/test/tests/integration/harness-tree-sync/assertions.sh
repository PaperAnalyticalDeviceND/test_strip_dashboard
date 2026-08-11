#!/usr/bin/env bash
# Assertions: sync trees declared in the manifest (issue #90).
#
# update/check must resolve scripts/test membership from the TEMPLATE REF
# (delivering new files, replacing stale ones, never touching host-added
# files under the tree); adopt must resolve it from the template checkout
# on disk and ADD the harness to adopted hosts.

STAGE="$SANDBOX/harness-tree-sync"
H="$STAGE/host"
REPO_ROOT_HTS="$(cd "$HERE/../.." && pwd)"

# --- update leg -------------------------------------------------------------
UP_LOG="$STAGE/update.log"
( cd "$H" && bash scripts/update-from-template.sh --template-url="$STAGE/template-src" ) \
    > "$UP_LOG" 2>&1
RC=$?

assert "update exits 0" "[ $RC -eq 0 ]"
assert "stale harness runner REPLACED with the template's" \
    "grep -qF 'NEW-RUNNER-MARKER' '$H/scripts/test/run.sh'"
assert "old runner content gone" \
    "! grep -qF 'OLD-RUNNER-MARKER' '$H/scripts/test/run.sh'"
assert "new harness lib delivered" \
    "[ -f '$H/scripts/test/lib/guard.sh' ]"
assert "new fixture delivered" \
    "[ -f '$H/scripts/test/tests/unit/sample/assertions.sh' ]"
assert "CI workflow delivered" \
    "[ -f '$H/.github/workflows/test-harness.yml' ]"
assert "host-owned feature test untouched (copy-no-delete)" \
    "grep -qF 'HOST-FEATURE-TEST-MARKER' '$H/scripts/test/tests/unit/myfeat/assertions.sh'"

# --- convergence + check leg ------------------------------------------------
UP2_LOG="$STAGE/update2.log"
( cd "$H" && bash scripts/update-from-template.sh --template-url="$STAGE/template-src" ) \
    > "$UP2_LOG" 2>&1
assert "second update reports zero changed files" \
    "grep -qF 'Changed (0):' '$UP2_LOG'"

CK_LOG="$STAGE/check.log"
( cd "$H" && bash scripts/check-template-version.sh --template-url="$STAGE/template-src" ) \
    > "$CK_LOG" 2>&1
CK_RC=$?
assert "check-template-version exits 0 (no drift incl. harness)" \
    "[ $CK_RC -eq 0 ]"

# --- adopt leg (dir-mode enumeration from the real template checkout) -------
# Template-checkout only: this leg runs the CHECKOUT's own scripts/adopt.sh
# against its own tree. In a derived project that binary is the frozen
# instantiation-vintage adopt (not manifest-synced, by design), so its
# behavior is unspecifiable here — observed in the field: a stub-era copy
# dry-runs and ADDs nothing. Same discriminator as manifest-shape's guard.
if [ ! -f "$REPO_ROOT_HTS/CLAUDE.md.template" ]; then
    skip "harness-tree-sync adopt leg" "not a template checkout (derived project; local adopt.sh vintage is unspecified)"
    return 0 2>/dev/null || true
fi
AD_LOG="$STAGE/adopt.log"
( cd "$STAGE/adopt-host" && \
  bash "$REPO_ROOT_HTS/scripts/adopt.sh" --target=. --apply --agent=none ) \
    > "$AD_LOG" 2>&1
AD_RC=$?
assert "adopt --apply exits 0" "[ $AD_RC -eq 0 ]"
assert "adopt ADDed the real harness runner" \
    "[ -f '$STAGE/adopt-host/scripts/test/run.sh' ]"
assert "adopt ADDed the harness lib" \
    "[ -f '$STAGE/adopt-host/scripts/test/lib/template.sh' ]"
assert "adopt ADDed the CI workflow" \
    "[ -f '$STAGE/adopt-host/.github/workflows/test-harness.yml' ]"
