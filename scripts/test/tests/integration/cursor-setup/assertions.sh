#!/usr/bin/env bash
# Assertions: run the real cursor/setup.sh against staged fixtures and verify:
#   - the host's CLAUDE.md is never touched (byte-identical across runs; the
#     old overlay injected subsections into it, and that writer is retired);
#   - the rules verification reports the full .cursor/rules/*.mdc set;
#   - identity comes from the on-disk wiki, not the clone directory name:
#     the checkout fixture's basename ('checkout') differs from its wiki
#     name ('glyph'), so a basename-derived lookup would fail Step 1 and
#     red the base-run assertions;
#   - the retired --legacy flag is rejected (the .cursorrules single-file
#     fallback was removed along with .cursorrules.template);
#   - a missing wiki fails loud, for the wiki reason.
#
# setup.sh locates the library from its own path, but takes the project
# root from the current directory, so each run cds into a fixture.

STAGE="$SANDBOX/cursor-setup"

# patch.sh declines to stage (no $STAGE dir) when the checkout is not the
# template — derived projects lack the shipped .cursor/rules set.
if [ ! -d "$STAGE" ]; then
    skip "cursor-setup assertions" "not a template checkout (derived project; cursor fixtures unavailable)"
    return 0 2>/dev/null || true
fi

# assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
REPO_ROOT_CU="$(cd "$HERE/../.." && pwd)"
SETUP="$REPO_ROOT_CU/wiki/agents/cursor/setup.sh"

assert "setup.sh exists"            "[ -f '$SETUP' ]"
assert "setup.sh passes bash -n"    "bash -n '$SETUP'"

# --- CLAUDE.md is host-owned: setup.sh must leave it byte-identical ---
# Snapshot BEFORE the first run, so an injection on run one (the retired
# behavior) fails the diff, not just a non-idempotent second run.
cp "$STAGE/checkout/CLAUDE.md" "$STAGE/checkout/CLAUDE.md.before"
OUT_BASE="$( cd "$STAGE/checkout" && bash "$SETUP" 2>&1 )"
RC_BASE=$?
assert "base run exits zero" "[ $RC_BASE -eq 0 ]"
assert "base run leaves CLAUDE.md byte-identical" \
    "diff -q '$STAGE/checkout/CLAUDE.md.before' '$STAGE/checkout/CLAUDE.md'"

# --- Rules verification: the full .mdc set is reported present ---
RULES_OK=0; case "$OUT_BASE" in *"all five present"*) RULES_OK=1 ;; esac
assert "base run reports all five .cursor/rules present" "[ $RULES_OK -eq 1 ]"
assert "memory-boundary.mdc is part of the staged rules set" \
    "[ -f '$STAGE/checkout/.cursor/rules/memory-boundary.mdc' ]"

# --- Second run: still no CLAUDE.md drift ---
( cd "$STAGE/checkout" && bash "$SETUP" ) >/dev/null 2>&1
assert "re-run leaves CLAUDE.md byte-identical" \
    "diff -q '$STAGE/checkout/CLAUDE.md.before' '$STAGE/checkout/CLAUDE.md'"

# --- --legacy is retired: rejected as an unknown option, writes nothing ---
OUT_LEGACY="$( cd "$STAGE/checkout" && bash "$SETUP" --legacy 2>&1 )"
RC_LEGACY=$?
assert "retired --legacy flag: setup.sh exits non-zero" "[ $RC_LEGACY -ne 0 ]"
LEGACY_MSG=0; case "$OUT_LEGACY" in *"Unknown option"*) LEGACY_MSG=1 ;; esac
assert "retired --legacy flag: rejected as an unknown option" "[ $LEGACY_MSG -eq 1 ]"
assert "retired --legacy flag: no .cursorrules written" \
    "[ ! -f '$STAGE/checkout/.cursorrules' ]"

# --- Fail-loud: no wiki present -> non-zero exit, for the wiki reason ---
ERR_NOWIKI="$( cd "$STAGE/nowiki" && bash "$SETUP" 2>&1 )"
RC=$?
assert "no wiki: setup.sh exits non-zero" "[ $RC -ne 0 ]"
NOWIKI_MSG=0; case "$ERR_NOWIKI" in *no\ wiki*|*"wiki not found"*) NOWIKI_MSG=1 ;; esac
assert "no wiki: failure names the missing wiki (not an unrelated error)" "[ $NOWIKI_MSG -eq 1 ]"
