#!/usr/bin/env bash
# Assertions: exercise install_feature and uninstall_feature against the
# bundled test-feature fixture. Verifies the contract: copy files, install
# the feature's rule file at .claude/rules/feature-<name>.md, copy CI
# workflow, record in .features-enabled, print deps; idempotency on
# re-install and re-uninstall; install + uninstall = identity; the host
# CLAUDE.md is never touched; without a .claude/ directory the rule step
# skips loudly and creates nothing.

PROJ="$SANDBOX/feature-flag-test-project"
NOCLAUDE_PROJ="$SANDBOX/feature-flag-noclaude-project"
RULE_DST="$PROJ/.claude/rules/feature-test-feature.md"
# assertions.sh is sourced by run.sh, so $HERE here = run.sh's HERE =
# scripts/test/. Two levels up is the template repo root.
REPO_ROOT_FFINFRA="$(cd "$HERE/../.." && pwd)"
INSTALL_LIB="$REPO_ROOT_FFINFRA/scripts/lib/install-feature.sh"
ENABLE_SCRIPT="$REPO_ROOT_FFINFRA/scripts/enable-feature.sh"
DISABLE_SCRIPT="$REPO_ROOT_FFINFRA/scripts/disable-feature.sh"
FEATURES_README="$REPO_ROOT_FFINFRA/features/README.md"

# --- Sanity: the infra files all exist and are syntactically valid ---
assert "scripts/lib/install-feature.sh exists" "[ -f '$INSTALL_LIB' ]"
assert "scripts/enable-feature.sh exists"      "[ -f '$ENABLE_SCRIPT' ]"
assert "scripts/disable-feature.sh exists"     "[ -f '$DISABLE_SCRIPT' ]"
assert "features/README.md exists"             "[ -f '$FEATURES_README' ]"

assert "install-feature.sh passes bash -n"  "bash -n '$INSTALL_LIB'"
assert "enable-feature.sh passes bash -n"   "bash -n '$ENABLE_SCRIPT'"
assert "disable-feature.sh passes bash -n"  "bash -n '$DISABLE_SCRIPT'"

assert "enable-feature.sh is executable"    "[ -x '$ENABLE_SCRIPT' ]"
assert "disable-feature.sh is executable"   "[ -x '$DISABLE_SCRIPT' ]"

# --- Helper: run a command in a project with FEATURES_DIR set to the fixture ---
_ff_run_in() {
    local proj="$1" cmd="$2"
    (cd "$proj" && FEATURES_DIR="$proj/_fixtures" bash -c "
        source '$INSTALL_LIB'
        $cmd
    ")
}
_ff_run_in_proj() { _ff_run_in "$PROJ" "$1"; }

# --- Step 1: install_feature test-feature ---
_ff_run_in_proj "install_feature test-feature" >/dev/null 2>&1
INSTALL_RC=$?
assert "install_feature test-feature exits 0"            "[ '$INSTALL_RC' -eq 0 ]"
assert "scripts/test-feature/ created"                   "[ -d '$PROJ/scripts/test-feature' ]"
assert "scripts/test-feature/greet.sh present"           "[ -f '$PROJ/scripts/test-feature/greet.sh' ]"
assert ".features-enabled file created"                  "[ -f '$PROJ/.features-enabled' ]"
assert ".features-enabled lists test-feature"            "grep -qFx 'test-feature' '$PROJ/.features-enabled'"
assert "rule file installed at .claude/rules/feature-test-feature.md" \
    "[ -f '$RULE_DST' ]"
assert "rule file carries the feature's content"         "grep -qF 'Test Feature (fixture)' '$RULE_DST'"
assert "CLAUDE.md untouched by install (byte-equal to baseline)" \
    "diff -q '$PROJ/CLAUDE.md' '$PROJ/CLAUDE.md.baseline' >/dev/null"
assert "CLAUDE.md gained no feature marker"              "! grep -qF '<!-- feature:test-feature -->' '$PROJ/CLAUDE.md'"
assert ".github/workflows/test-feature.yml created"      "[ -f '$PROJ/.github/workflows/test-feature.yml' ]"

# --- Step 2: idempotent install (re-run, should not duplicate) ---
LINES_BEFORE=$(wc -l < "$PROJ/.features-enabled")
_ff_run_in_proj "install_feature test-feature" >/dev/null 2>&1
RE_INSTALL_RC=$?
LINES_AFTER=$(wc -l < "$PROJ/.features-enabled")

assert "idempotent install: exits 0"                          "[ '$RE_INSTALL_RC' -eq 0 ]"
assert "idempotent install: .features-enabled not duplicated" "[ '$LINES_BEFORE' -eq '$LINES_AFTER' ]"
assert "idempotent install: rule file still present"          "[ -f '$RULE_DST' ]"

# --- Step 3: uninstall_feature test-feature ---
_ff_run_in_proj "uninstall_feature test-feature" >/dev/null 2>&1
UNINSTALL_RC=$?

assert "uninstall_feature exits 0"                     "[ '$UNINSTALL_RC' -eq 0 ]"
assert "scripts/test-feature/ removed"                 "[ ! -d '$PROJ/scripts/test-feature' ]"
assert ".features-enabled removed (was empty)"         "[ ! -f '$PROJ/.features-enabled' ]"
assert "rule file removed"                             "[ ! -f '$RULE_DST' ]"
assert "sibling rule keep-me.md survives uninstall"    "[ -f '$PROJ/.claude/rules/keep-me.md' ]"
assert ".claude/rules/ kept while a sibling remains"   "[ -d '$PROJ/.claude/rules' ]"
assert ".github/workflows/test-feature.yml removed"    "[ ! -f '$PROJ/.github/workflows/test-feature.yml' ]"

# --- Step 4: install + uninstall = identity ---
assert "CLAUDE.md byte-equivalent to baseline after install+uninstall" \
    "diff -q '$PROJ/CLAUDE.md' '$PROJ/CLAUDE.md.baseline' >/dev/null"
assert "keep-me.md byte-equivalent to baseline after install+uninstall" \
    "diff -q '$PROJ/.claude/rules/keep-me.md' '$PROJ/keep-me.md.baseline' >/dev/null"

# --- Step 5: idempotent uninstall (re-run, no error) ---
_ff_run_in_proj "uninstall_feature test-feature" >/dev/null 2>&1
IDEMP_UNINSTALL_RC=$?
assert "idempotent uninstall: re-run exits 0"          "[ '$IDEMP_UNINSTALL_RC' -eq 0 ]"

# --- Step 6: error handling — install_feature on non-existent feature ---
_ff_run_in_proj "install_feature nonexistent-feature-name" >/dev/null 2>&1
NOTFOUND_RC=$?
assert "install_feature on nonexistent feature exits non-zero" "[ '$NOTFOUND_RC' -ne 0 ]"

# --- Step 7: error handling — install_feature called with no args ---
_ff_run_in_proj "install_feature" >/dev/null 2>&1
NOARG_RC=$?
assert "install_feature with no name exits non-zero"           "[ '$NOARG_RC' -ne 0 ]"

# --- Step 8: no .claude/ directory -> rule step skips loudly, creates nothing ---
NOCLAUDE_OUT="$SANDBOX/feature-flag-noclaude-install.out"
_ff_run_in "$NOCLAUDE_PROJ" "install_feature test-feature" > "$NOCLAUDE_OUT" 2>&1
NOCLAUDE_RC=$?
assert "no-.claude install exits 0"                    "[ '$NOCLAUDE_RC' -eq 0 ]"
assert "no-.claude install does NOT create .claude/"   "[ ! -d '$NOCLAUDE_PROJ/.claude' ]"
assert "no-.claude install says the rule step was skipped" \
    "grep -qF 'skipped installing the rule file' '$NOCLAUDE_OUT'"
assert "no-.claude install still copies files"         "[ -f '$NOCLAUDE_PROJ/scripts/test-feature/greet.sh' ]"
assert "no-.claude install still records the feature"  "grep -qFx 'test-feature' '$NOCLAUDE_PROJ/.features-enabled'"

_ff_run_in "$NOCLAUDE_PROJ" "uninstall_feature test-feature" >/dev/null 2>&1
NOCLAUDE_UN_RC=$?
assert "no-.claude uninstall exits 0"                  "[ '$NOCLAUDE_UN_RC' -eq 0 ]"
