#!/usr/bin/env bash
# Assertions: a malformed grants YAML should not crash the parser. The
# minimal awk reader in adopt.sh picks up valid lines and silently
# skips garbage (missing values, missing keys, non-grants prose).
# The valid '.claude/settings.json: merge' entry still applies.

STAGE="$SANDBOX/adopt-apply-malformed-grants"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
RC_FILE="$STAGE/rc.txt"

# --- Script did not crash on the malformed YAML ---
assert "apply produced output" "[ -f '$OUT' ]"
assert "apply did not abort -- ran to completion (RC=0)" \
    "[ \"\$(cat '$RC_FILE')\" = 0 ]"

# --- The valid entry was picked up and applied ---
assert "header reports the grants file was detected" \
    "grep -qE 'Grants file:.*\\.llm-wiki-adopt-grants\\.yml' '$OUT'"
assert "TOUCH block lists .claude/settings.json (the only valid entry)" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qE '~ +\\.claude/settings\\.json +merge'"
assert "manifest reports settings.json merge as created from canonical" \
    "grep -qF '.claude/settings.json (merge): created from canonical via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md'"
assert "host .gitignore untouched (still only the host's own rule)" \
    "[ \"\$(cat '$HOST/.gitignore')\" = '*.pyc' ]"
assert "wiki/.gitignore was ADDed with the *.wiki/ rule" \
    "grep -qFx '*.wiki/' '$HOST/wiki/.gitignore'"

# --- Garbage lines did NOT classify ---
# 'CLAUDE.md:' (no value) should be skipped, not classified.
# 'malformed line with no colon' should be skipped, ditto.
# ': value-without-key' should be skipped.
# 'trailing garbage at the bottom' should be skipped.
assert "manifest does NOT list CLAUDE.md (was malformed key with no value)" \
    "! grep -qF -- '- CLAUDE.md (' '$HOST/.llm-wiki-adopt-log.md'"
assert "TOUCH block does NOT list a 'malformed' or 'garbage' entry" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qiE 'malformed|garbage|value-without-key'"
assert "GRANT WARNINGS section does NOT report nonsense entries either" \
    "! awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qiE 'malformed|garbage|value-without-key'"

# --- Apply completed successfully end-to-end despite the YAML mess ---
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest reports overlay setup ran (whether applied or skipped)" \
    "grep -qE -- '- overlay setup: (applied|skipped|failed)' '$HOST/.llm-wiki-adopt-log.md'"
