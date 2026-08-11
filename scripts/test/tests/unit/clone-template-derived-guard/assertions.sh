#!/usr/bin/env bash
# Assertions: verify clone_template's derived-project guard (issue #15).
# The guard returns 1 when MVP_TEMPLATE_LOCAL points at a derived project
# (scripts/instantiate.sh absent; it self-deletes at instantiation), and 0
# when it points at the canonical template (scripts/instantiate.sh present).
#
# This is a regression test: if a future refactor of clone_template
# breaks the guard, the smoke template-bootstrap and instantiate-agent-none
# tests start producing 16 spurious failures whenever the harness is
# run inside a derived project. Catching it here keeps that bug from
# returning silently.

ROOT="$SANDBOX/clone-template-guard"
TEMPL="$ROOT/fake-template"
DERIVED="$ROOT/fake-derived"

# assertions.sh is sourced by run.sh, so $HERE = scripts/test/.
TEMPLATE_LIB="$HERE/lib/template.sh"

assert "lib/template.sh exists"             "[ -f '$TEMPLATE_LIB' ]"
assert "lib/template.sh passes bash -n"     "bash -n '$TEMPLATE_LIB'"

# --- Sanity: the fixtures from patch.sh are present ---
assert "fake-template fixture has scripts/instantiate.sh" \
    "[ -f '$TEMPL/scripts/instantiate.sh' ]"
assert "fake-derived fixture has no scripts/instantiate.sh" \
    "[ ! -f '$DERIVED/scripts/instantiate.sh' ]"
assert "fake-derived fixture has CLAUDE.md (guard must not key on it)" \
    "[ -f '$DERIVED/CLAUDE.md' ]"

# --- Helper: run clone_template in a subshell with given inputs ---
# Returns the exit code of clone_template.
_clone_with_local() {
    local local_path="$1"
    local target="$2"
    local stderr_file="$3"
    (
        # Isolate: only MVP_TEMPLATE_LOCAL set, no network fallback URL.
        # We never want the network branch to run from a unit test.
        unset MVP_TEMPLATE_REPO
        export MVP_TEMPLATE_LOCAL="$local_path"
        # Point DEFAULT_TEMPLATE_REPO at a bogus URL inside the function's
        # scope so that if the guard fails to trigger, the network branch
        # also fails (no silent passes via accidental network access).
        export _UNIT_FORCE_BOGUS=1
        source "$TEMPLATE_LIB"
        if [[ -n "${_UNIT_FORCE_BOGUS:-}" ]]; then
            DEFAULT_TEMPLATE_REPO="https://invalid.invalid/no-such-repo.git"
        fi
        clone_template "$target" 2>"$stderr_file"
    )
}

# --- Case 1: fake-template should be cloneable (returns 0, creates target) ---
TARGET_OK="$ROOT/out-template"
rm -rf "$TARGET_OK"
STDERR_OK="$ROOT/stderr-template.log"
_clone_with_local "$TEMPL" "$TARGET_OK" "$STDERR_OK"
RC_OK=$?
assert_eq "clone_template returns 0 for fake-template (template-like input)" \
    "0" "$RC_OK"
assert "clone_template created target dir for fake-template" \
    "[ -d '$TARGET_OK' ]"
assert "clone_template copied scripts/instantiate.sh into target" \
    "[ -f '$TARGET_OK/scripts/instantiate.sh' ]"

# --- Case 2: fake-derived should be refused (returns 1, no target created) ---
TARGET_NO="$ROOT/out-derived"
rm -rf "$TARGET_NO"
STDERR_NO="$ROOT/stderr-derived.log"
_clone_with_local "$DERIVED" "$TARGET_NO" "$STDERR_NO"
RC_NO=$?
assert_eq "clone_template returns 1 for fake-derived (derived-like input)" \
    "1" "$RC_NO"
assert "clone_template did NOT create target dir for fake-derived" \
    "[ ! -d '$TARGET_NO' ]"
assert "clone_template stderr mentions 'derived' on the refusal path" \
    "grep -qi 'derived' '$STDERR_NO'"
assert "clone_template stderr references issue #15 on the refusal path" \
    "grep -qF 'issue #15' '$STDERR_NO'"

# --- Case 3: derived project WITHOUT CLAUDE.md is still refused ---
# The normal shape of a new-style derived project (instantiate no longer
# creates CLAUDE.md). The retired CLAUDE.md-based discriminator passed
# this through as template-like; the instantiate.sh-based one refuses it.
DERIVED_BARE="$ROOT/fake-derived-no-claude"
TARGET_BARE="$ROOT/out-derived-no-claude"
rm -rf "$TARGET_BARE"
STDERR_BARE="$ROOT/stderr-derived-no-claude.log"
_clone_with_local "$DERIVED_BARE" "$TARGET_BARE" "$STDERR_BARE"
RC_BARE=$?
assert_eq "clone_template returns 1 for a CLAUDE.md-less derived project" \
    "1" "$RC_BARE"
assert "clone_template did NOT create target dir for CLAUDE.md-less derived" \
    "[ ! -d '$TARGET_BARE' ]"
