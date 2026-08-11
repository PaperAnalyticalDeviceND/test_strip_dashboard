#!/usr/bin/env bash
# Assertions: run the real setup.sh against staged fixtures and verify the
# shared-library wiring:
#   - identity comes from the on-disk wiki, not the clone directory name;
#   - --seed-memory uses the corrected encoding under a hermetic
#     CLAUDE_CONFIG_DIR (never touches the real ~/.claude);
#   - a missing wiki fails loud;
#   - a settings.json-only merge still flags a change (audit #9).
#
# setup.sh locates the library from its own path, but takes the project
# root from the current directory, so each run cds into a fixture.

STAGE="$SANDBOX/claude-code-setup"
# assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
REPO_ROOT_CC="$(cd "$HERE/../.." && pwd)"
SETUP="$REPO_ROOT_CC/wiki/agents/claude-code/setup.sh"

assert "setup.sh exists"            "[ -f '$SETUP' ]"
assert "setup.sh passes bash -n"    "bash -n '$SETUP'"

# --- Base mode: CLAUDE.md is never touched anymore ---
# The behavioral instructions ship as .claude/rules/*.md; base mode only
# verifies the wiki, commands, and skills. Identity (wiki name vs clone
# dir basename) is proven by the --seed-memory leg below.
( cd "$STAGE/checkout" && CLAUDE_CONFIG_DIR="$STAGE/cfg" bash "$SETUP" ) >/dev/null 2>&1
RC_BASE=$?
assert "base mode exits 0 with a wiki present" "[ $RC_BASE -eq 0 ]"
assert "base mode did NOT write the wiki name into CLAUDE.md" \
    "! grep -qF 'wiki/sigil.wiki/' '$STAGE/checkout/CLAUDE.md'"
assert "base mode injected NO lw sentinels into CLAUDE.md" \
    "! grep -qF '<!-- lw:' '$STAGE/checkout/CLAUDE.md'"
assert "baseline CLAUDE.md content preserved" \
    "grep -qF 'Baseline content that must be preserved' '$STAGE/checkout/CLAUDE.md'"

# --- Memory: --seed-memory honors CLAUDE_CONFIG_DIR and uses the wiki name ---
( cd "$STAGE/checkout" && CLAUDE_CONFIG_DIR="$STAGE/cfg" bash "$SETUP" --seed-memory ) >/dev/null 2>&1
MEMFILE="$(find "$STAGE/cfg/projects" -name wiki-as-project-memory.md 2>/dev/null | head -1)"
assert "memory: seeded under CLAUDE_CONFIG_DIR (hermetic)" "[ -n '$MEMFILE' ]"
assert "memory: seed body uses the wiki name" "grep -qF 'wiki/sigil.wiki/' '$MEMFILE'"
MEMINDEX="$(dirname "$MEMFILE")/MEMORY.md"
assert "memory: MEMORY.md index header uses the wiki name (sigil)" "grep -qF 'sigil' '$MEMINDEX'"

# --- Fail-loud: no wiki present -> non-zero exit ---
( cd "$STAGE/nowiki" && CLAUDE_CONFIG_DIR="$STAGE/cfg" bash "$SETUP" ) >/dev/null 2>&1
RC=$?
assert "no wiki: setup.sh exits non-zero" "[ $RC -ne 0 ]"

# --- Audit #9: a settings.json-only merge still reports a change ---
if command -v jq >/dev/null 2>&1; then
    OUT="$( cd "$STAGE/merge" && CLAUDE_CONFIG_DIR="$STAGE/cfg" bash "$SETUP" --hook 2>&1 )"
    # setup.sh now registers each hook in its own group; the per-hook message
    # is "merged <file> SessionStart hook (via jq)". Match the common suffix.
    MERGED=0;    case "$OUT" in *"SessionStart hook (via jq)"*) MERGED=1 ;; esac
    NEXTSTEPS=0; case "$OUT" in *"Next steps:"*) NEXTSTEPS=1 ;; esac
    assert "merge: the jq merge is reported"                       "[ $MERGED -eq 1 ]"
    assert "merge-only change still prints 'Next steps' (audit #9)" "[ $NEXTSTEPS -eq 1 ]"
else
    skip "merge-only change still prints 'Next steps' (audit #9)" "jq not available"
fi
