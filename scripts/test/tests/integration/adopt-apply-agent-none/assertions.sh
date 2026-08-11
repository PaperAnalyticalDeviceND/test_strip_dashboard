#!/usr/bin/env bash
# Assertions: --agent=none on a virgin host with a merge grant. Overlay
# setup must NOT run; the merge TOUCH must be recorded as 'skipped' (not
# failed, not applied); the host's CLAUDE.md must remain entirely
# unchanged (it is not a grant target anymore).

STAGE="$SANDBOX/adopt-apply-agent-none"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "header reports Agent overlay: none" \
    "grep -qF 'Agent overlay:    none' '$OUT'"

# Overlay setup is skipped entirely (no claude-code setup.sh invocation).
assert "manifest reports overlay setup as skipped (--agent=none)" \
    "grep -qF -- '- overlay setup: skipped' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest detail mentions '--agent=none' as the reason" \
    "grep -qF -- '--agent=none, no overlay' '$HOST/.llm-wiki-adopt-log.md'"

# CLAUDE.md never classifies (managed-block grant retired).
assert "manifest does NOT list a CLAUDE.md TOUCH at all" \
    "! grep -qF -- '- CLAUDE.md (' '$HOST/.llm-wiki-adopt-log.md'"

# The merge grant records 'skipped', not 'applied' and not 'failed'.
assert "manifest reports settings.json merge as skipped" \
    "grep -qF '.claude/settings.json (merge): skipped' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT report merge as applied" \
    "! grep -qF '.claude/settings.json (merge): applied' '$HOST/.llm-wiki-adopt-log.md'"

# Host CLAUDE.md must remain entirely host-authored: no sentinels injected.
assert "host CLAUDE.md has NO lw:memory-boundary sentinel (overlay was skipped)" \
    "! grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md'"
assert "host CLAUDE.md has NO lw:wiki-maintenance sentinel" \
    "! grep -qF '<!-- lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"

# Host's prose preserved.
assert "host title preserved" \
    "grep -qFx '# Agent None Host' '$HOST/CLAUDE.md'"
assert "host conventions section preserved" \
    "grep -qFx '## Project conventions' '$HOST/CLAUDE.md'"
assert "host's settings.json was NOT modified (merge was skipped)" \
    "grep -qF '\"theme\": \"host\"' '$HOST/.claude/settings.json' && \\
     ! grep -qF 'SessionStart' '$HOST/.claude/settings.json'"

# Overlay-gated ADD entries did not leak past --agent=none. The host has
# .claude/ (its own settings.json), so directory presence cannot gate this;
# only the assemble(agent) filter keeps overlay files out of the ADD set.
assert "no .claude/rules/ overlay files ADDed under --agent=none" \
    "[ ! -e '$HOST/.claude/rules/wiki-as-memory.md' ]"

# Phase 1 ADD still ran -- init-wiki status captured as well.
assert "manifest records init-wiki status" \
    "grep -qE -- '- init-wiki: (applied|already-present)' '$HOST/.llm-wiki-adopt-log.md'"
