#!/usr/bin/env bash
# Assertions: exercise install_feature and uninstall_feature against the
# REAL features/agent-comms/ in this repo. Mirrors tests/unit/feature-flag-infra/
# but points at the real feature, not the throwaway _fixtures/test-feature stub.
# The project here has .claude/ but no .claude/rules/, so this test also
# covers install creating the rules directory and uninstall removing it
# again once empty.
#
# Sourced by run.sh, so $HERE = scripts/test/.

PROJ="$SANDBOX/agent-comms-test-project"
RULE_DST="$PROJ/.claude/rules/feature-agent-comms.md"

REPO_ROOT_AC="$(cd "$HERE/../.." && pwd)"
INSTALL_LIB="$REPO_ROOT_AC/scripts/lib/install-feature.sh"
FEATURES_PARENT_DIR="$REPO_ROOT_AC/features"
FEATURE_DIR="$FEATURES_PARENT_DIR/agent-comms"

# --- Sanity: real feature exists and is well-formed ---
assert "features/agent-comms/feature.json exists"        "[ -f '$FEATURE_DIR/feature.json' ]"
assert "features/agent-comms/rule.md exists"             "[ -f '$FEATURE_DIR/rule.md' ]"
assert "features/agent-comms/code/ exists"               "[ -d '$FEATURE_DIR/code' ]"
assert "features/agent-comms/code/ask.sh exists"         "[ -f '$FEATURE_DIR/code/ask.sh' ]"
assert "features/agent-comms/code/enroll.sh exists"      "[ -f '$FEATURE_DIR/code/enroll.sh' ]"
assert "features/agent-comms/ci/agent-comms.yml exists"  "[ -f '$FEATURE_DIR/ci/agent-comms.yml' ]"

# Bash syntax sanity for the scripts we will ship
assert "ask.sh passes bash -n"     "bash -n '$FEATURE_DIR/code/ask.sh'"
assert "enroll.sh passes bash -n"  "bash -n '$FEATURE_DIR/code/enroll.sh'"

# --- Helper: run a command in $PROJ with FEATURES_DIR pointed at real features/ ---
_ac_run_in_proj() {
    (cd "$PROJ" && FEATURES_DIR="$FEATURES_PARENT_DIR" bash -c "
        source '$INSTALL_LIB'
        $1
    ")
}

# --- Step 1: install_feature agent-comms ---
_ac_run_in_proj "install_feature agent-comms" >/dev/null 2>&1
INSTALL_RC=$?
assert "install_feature agent-comms exits 0"             "[ '$INSTALL_RC' -eq 0 ]"
assert "scripts/agent-comms/ created"                    "[ -d '$PROJ/scripts/agent-comms' ]"
assert "scripts/agent-comms/ask.sh installed"            "[ -f '$PROJ/scripts/agent-comms/ask.sh' ]"
assert "scripts/agent-comms/enroll.sh installed"         "[ -f '$PROJ/scripts/agent-comms/enroll.sh' ]"
assert "scripts/agent-comms/README.md installed"         "[ -f '$PROJ/scripts/agent-comms/README.md' ]"
assert ".features-enabled file created"                  "[ -f '$PROJ/.features-enabled' ]"
assert ".features-enabled lists agent-comms"             "grep -qFx 'agent-comms' '$PROJ/.features-enabled'"
assert "rule file installed at .claude/rules/feature-agent-comms.md" \
    "[ -f '$RULE_DST' ]"
assert "rule file carries the feature's content"         "grep -qF 'Cross-agent communication' '$RULE_DST'"
assert "CLAUDE.md untouched by install (byte-equal to baseline)" \
    "diff -q '$PROJ/CLAUDE.md' '$PROJ/CLAUDE.md.baseline' >/dev/null"
assert "CLAUDE.md gained no feature marker"              "! grep -qF '<!-- feature:agent-comms -->' '$PROJ/CLAUDE.md'"
assert ".github/workflows/agent-comms.yml created"       "[ -f '$PROJ/.github/workflows/agent-comms.yml' ]"

# --- Step 2: idempotent install (re-run, no duplication) ---
LINES_BEFORE=$(wc -l < "$PROJ/.features-enabled")
_ac_run_in_proj "install_feature agent-comms" >/dev/null 2>&1
RE_INSTALL_RC=$?
LINES_AFTER=$(wc -l < "$PROJ/.features-enabled")

assert "idempotent install: exits 0"                          "[ '$RE_INSTALL_RC' -eq 0 ]"
assert "idempotent install: .features-enabled not duplicated" "[ '$LINES_BEFORE' -eq '$LINES_AFTER' ]"
assert "idempotent install: rule file still present"          "[ -f '$RULE_DST' ]"

# --- Step 3: uninstall_feature agent-comms ---
_ac_run_in_proj "uninstall_feature agent-comms" >/dev/null 2>&1
UNINSTALL_RC=$?

assert "uninstall_feature exits 0"                            "[ '$UNINSTALL_RC' -eq 0 ]"
assert "scripts/agent-comms/ removed"                         "[ ! -d '$PROJ/scripts/agent-comms' ]"
assert ".features-enabled removed (was empty)"                "[ ! -f '$PROJ/.features-enabled' ]"
assert "rule file removed"                                    "[ ! -f '$RULE_DST' ]"
assert ".claude/rules/ removed once empty"                    "[ ! -d '$PROJ/.claude/rules' ]"
assert ".claude/ itself survives uninstall"                   "[ -d '$PROJ/.claude' ]"
assert ".github/workflows/agent-comms.yml removed"            "[ ! -f '$PROJ/.github/workflows/agent-comms.yml' ]"

# --- Step 4: install + uninstall = identity (byte-equivalent CLAUDE.md) ---
assert "CLAUDE.md byte-equivalent to baseline after install+uninstall" \
    "diff -q '$PROJ/CLAUDE.md' '$PROJ/CLAUDE.md.baseline' >/dev/null"

# --- Step 5: idempotent uninstall (re-run, no error) ---
_ac_run_in_proj "uninstall_feature agent-comms" >/dev/null 2>&1
IDEMP_UNINSTALL_RC=$?
assert "idempotent uninstall: re-run exits 0"                 "[ '$IDEMP_UNINSTALL_RC' -eq 0 ]"
