#!/usr/bin/env bash
# Assertions: when a granted target is absent on disk, adopt classifies
# it as a regular TOUCH (no MISSING category) and the apply path
# creates it from the canonical payload / via the overlay's setup.sh
# --hook. The grant governs HOW to safely modify a host file when one
# exists; absence just means there is no host content to preserve, so
# the canonical install fires.
#
# PR #51 redesign (items 3, 4, 5): MISSING no longer means moot.

STAGE="$SANDBOX/adopt-apply-touch-missing-target"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"

# Dry-run TOUCH row marks the absent target with the canonical-install
# notice, so the user sees the difference without it being moot.
assert "TOUCH row marks .claude/settings.json as 'absent; will create from canonical'" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.claude/settings.json' | : ; \\
     awk '/^TOUCH/,/^\$/' '$OUT' | grep -q '.claude/settings.json.*\\[absent; will create from canonical\\]'"

# The TOUCH section LISTS .claude/settings.json (it is no longer absent
# from the TOUCH dispatch, just marked absent in the host).
assert "TOUCH section LISTS .claude/settings.json (regular TOUCH, not moot)" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.claude/settings.json'"

# GRANT WARNINGS section is silent on absent-target cases (it now only
# fires for TOUCH_INVALID -- unknown target or type mismatch).
assert "GRANT WARNINGS section does NOT list .claude/settings.json as moot" \
    "! grep -qF '? .claude/settings.json' '$OUT'"

# Adopt DID create .claude/settings.json from canonical (overlay's
# setup.sh --hook handles the absent-file case).
assert "adopt CREATED .claude/settings.json from canonical (absent grant fulfilled)" \
    "[ -f '$HOST/.claude/settings.json' ]"
assert ".claude/settings.json content includes a SessionStart hook entry" \
    "grep -qF 'SessionStart' '$HOST/.claude/settings.json'"

# adopt --apply completed end-to-end (manifest written).
assert "manifest exists (adopt --apply completed)" \
    "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"

# The manifest reports settings.json TOUCH applied with the new
# 'created from canonical' status string.
assert "manifest lists .claude/settings.json (merge) as created from canonical" \
    "grep -qF '.claude/settings.json (merge): created from canonical via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md'"
