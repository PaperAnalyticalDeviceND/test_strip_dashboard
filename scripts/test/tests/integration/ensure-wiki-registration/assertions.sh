#!/usr/bin/env bash
# Assertions: ensure-wiki SessionStart registration must scope correctly.
#
# Runs the real setup.sh --hook against a project whose settings.json already
# has a SessionStart entry matched to "resume" only, then inspects the merged
# settings.json. The bug this guards: folding the wiki hooks into the existing
# entry makes them inherit its "resume" matcher, so ensure-wiki never runs on
# startup (the case that matters most for a fresh checkout).

STAGE="$SANDBOX/ensure-wiki-registration"
# assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
REPO_ROOT_R="$(cd "$HERE/../.." && pwd)"
SETUP="$REPO_ROOT_R/wiki/agents/claude-code/setup.sh"
NARROW="$STAGE/narrow"
SET="$NARROW/.claude/settings.json"

if [ ! -f "$SETUP" ] || [ ! -d "$NARROW" ]; then
    skip "ensure-wiki registration" "fixture or setup.sh missing"
    return 0 2>/dev/null || true
fi
if ! command -v jq >/dev/null 2>&1; then
    skip "ensure-wiki registration: matcher scoping" "jq not available"
    return 0 2>/dev/null || true
fi

( cd "$NARROW" && CLAUDE_CONFIG_DIR="$STAGE/cfg" bash "$SETUP" --hook ) >/dev/null 2>&1

assert "merged settings.json is still valid JSON" \
    "jq -e . '$SET' >/dev/null"

# The user's pre-existing resume hook must survive the merge untouched.
assert "pre-existing 'resume' hook is preserved" \
    "jq -e '[.hooks.SessionStart[].hooks[].command] | any(test(\"existing-resume-hook.sh\"))' '$SET' >/dev/null"

# Core guard (#2): ensure-wiki must live in an entry whose matcher admits
# 'startup' — empty, '*', absent, or a pattern containing 'startup'. If it was
# folded into the pre-existing 'resume'-only entry, this select excludes it and
# the assertion fails.
STARTUP_SELECT='[.hooks.SessionStart[] | select((.matcher // "") as $m | ($m=="" or $m=="*" or ($m|test("startup")))) | .hooks[].command]'
assert "ensure-wiki runs on startup (not trapped under the resume matcher)" \
    "jq -e '$STARTUP_SELECT | any(test(\"ensure-wiki.py\"))' '$SET' >/dev/null"

# The surfacing hook should run on ALL sources (no/loose matcher), so the wiki
# index is re-injected after /clear and /compact, not just startup+resume.
ALL_SELECT='[.hooks.SessionStart[] | select((.matcher // "") as $m | ($m=="" or $m=="*")) | .hooks[].command]'
assert "surfacing hook runs on all sources" \
    "jq -e '$ALL_SELECT | any(test(\"session-start.sh\"))' '$SET' >/dev/null"

# ensure-wiki should NOT be globally unmatched-and-also-resume-bound: confirm it
# is not silently dropped (belt-and-suspenders against a merge that no-ops).
assert "ensure-wiki is registered somewhere in SessionStart" \
    "jq -e '[.hooks.SessionStart[].hooks[].command] | any(test(\"ensure-wiki.py\"))' '$SET' >/dev/null"
