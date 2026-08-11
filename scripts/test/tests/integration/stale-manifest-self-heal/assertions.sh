#!/usr/bin/env bash
# Assertions: update-from-template.sh must detect a PRESENT-but-STALE local
# manifest (pre-#76: does not list itself), assemble this run's file list
# from the template ref's manifest instead, and thereby deliver both the
# manifest replacement and the files only the new manifest lists. Without
# the stale trigger the run uses the old list and the host is stuck forever.

STAGE="$SANDBOX/stale-manifest-self-heal"
H="$STAGE/host"

RUN1_LOG="$STAGE/run1.log"
( cd "$H" && bash scripts/update-from-template.sh --template-url="$STAGE/template-src" ) \
    > "$RUN1_LOG" 2>&1
RC1=$?

assert "run 1 exits 0" "[ $RC1 -eq 0 ]"
assert "run 1 announces the stale-manifest self-heal" \
    "grep -qF 'predates #76' '$RUN1_LOG'"

# The core of the fix: files only the CURRENT manifest lists arrive.
assert "manifest on disk replaced (now lists itself)" \
    "grep -qF '\"scripts/lib/template-manifest.sh\"' '$H/scripts/lib/template-manifest.sh'"
assert "wiki/Edge-Types.md.template delivered" \
    "[ -f '$H/wiki/Edge-Types.md.template' ]"
assert ".claude/commands/ask.md delivered" \
    "[ -f '$H/.claude/commands/ask.md' ]"
assert "scripts/wiki-reciprocity.py delivered" \
    "[ -f '$H/scripts/wiki-reciprocity.py' ]"

# Control: the normal sync path is unaffected (old-list file synced with
# {{REPO_NAME}} substituted from the on-disk wiki name).
CTRL="$H/.claude/skills/wiki-experiment/SKILL.md"
assert "control: old-list file synced" "grep -q 'skill for stalehost' '$CTRL'"
assert "control: no {{REPO_NAME}} left" "! grep -q '{{REPO_NAME}}' '$CTRL'"

# Convergence: a second run sources the now-healthy on-disk manifest, does
# not re-trigger the self-heal, and reports nothing to change.
RUN2_LOG="$STAGE/run2.log"
( cd "$H" && bash scripts/update-from-template.sh --template-url="$STAGE/template-src" ) \
    > "$RUN2_LOG" 2>&1
RC2=$?

assert "run 2 exits 0" "[ $RC2 -eq 0 ]"
assert "run 2 does NOT re-trigger the self-heal" \
    "! grep -qF 'predates #76' '$RUN2_LOG'"
assert "run 2 reports zero changed files" \
    "grep -qF 'Changed (0):' '$RUN2_LOG'"
