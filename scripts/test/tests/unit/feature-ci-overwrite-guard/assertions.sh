#!/usr/bin/env bash
# Assertions: install_feature must refuse to overwrite a pre-existing host
# CI workflow of the same basename (issue #68), symmetric with the guards
# it already has for files.destination and tests.destination. Control case:
# a project without the collision still installs normally.

STAGE="$SANDBOX/feature-ci-overwrite-guard"
REPO_ROOT_CIGUARD="$(cd "$HERE/../.." && pwd)"
INSTALL_LIB="$REPO_ROOT_CIGUARD/scripts/lib/install-feature.sh"

_cig_run() {
    local proj="$1" cmd="$2"
    (cd "$STAGE/$proj" && FEATURES_DIR="$STAGE/$proj/_fixtures" bash -c "
        source '$INSTALL_LIB'
        $cmd
    ")
}

# --- Collision case: host already has .github/workflows/test-feature.yml ---
CIG_OUT="$STAGE/collision-install.out"
_cig_run collision "install_feature test-feature" > "$CIG_OUT" 2>&1
CIG_RC=$?

assert "collision: install_feature exits non-zero (refuses)" \
    "[ '$CIG_RC' -ne 0 ]"
assert "collision: host workflow content survived untouched" \
    "grep -qF 'HOST-OWNED-WORKFLOW-MARKER' '$STAGE/collision/.github/workflows/test-feature.yml'"
assert "collision: feature bytes did NOT land in the host workflow" \
    "! grep -qF 'test-feature workflow placeholder' '$STAGE/collision/.github/workflows/test-feature.yml'"
assert "collision: error names the blocked destination" \
    "grep -qF \"Error: CI workflow destination '.github/workflows/test-feature.yml' already exists\" '$CIG_OUT'"
assert "collision: error says it refuses to overwrite" \
    "grep -qiF 'refusing to overwrite' '$CIG_OUT'"
assert "collision: refused install is not recorded in .features-enabled" \
    "! grep -qFx 'test-feature' '$STAGE/collision/.features-enabled' 2>/dev/null"

# --- Control case: no collision -> normal install path unaffected ---
_cig_run clean "install_feature test-feature" >/dev/null 2>&1
CIG_CLEAN_RC=$?

assert "clean: install_feature exits 0" \
    "[ '$CIG_CLEAN_RC' -eq 0 ]"
assert "clean: CI workflow copied" \
    "[ -f '$STAGE/clean/.github/workflows/test-feature.yml' ]"
assert "clean: .features-enabled lists test-feature" \
    "grep -qFx 'test-feature' '$STAGE/clean/.features-enabled'"
