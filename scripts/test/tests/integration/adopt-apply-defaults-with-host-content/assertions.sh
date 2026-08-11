#!/usr/bin/env bash
# Assertions: with the integration files preauthored AND no grants
# file, the default-grants path classifies .claude/settings.json as
# TOUCH with was_absent=0, and the apply path MODIFIES it (preserving
# host content) rather than 'create from canonical'. The host's
# CLAUDE.md and .gitignore are not grant targets at all and must come
# through untouched. Verifies the defaults path discriminates absent
# vs present targets correctly.

STAGE="$SANDBOX/adopt-apply-defaults-with-host-content"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "header reports grants source as 'defaults'" \
    "grep -qE 'Grants file:\\s+defaults' '$OUT'"

# TOUCH rows do NOT carry the '[absent; will create from canonical]'
# marker since the host has the granted file, and the retired grants
# never classify.
assert "TOUCH block does NOT list CLAUDE.md (grant retired)" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md'"
assert "TOUCH block does NOT list .gitignore (grant retired)" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.gitignore'"
assert "TOUCH row for .claude/settings.json does NOT show absent marker" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -q '\\.claude/settings.json.*\\[absent'"

# Manifest uses 'applied' (not 'created from canonical').
assert "manifest does NOT list a CLAUDE.md TOUCH (managed-block grant retired)" \
    "! grep -qF -- '- CLAUDE.md (' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT list a .gitignore TOUCH (no such grant anymore)" \
    "! grep -qF -- '- .gitignore (' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports settings.json as applied (not created from canonical)" \
    "grep -qF '.claude/settings.json (merge): applied via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md' && \\
     ! grep -qF '.claude/settings.json (merge): created from canonical' '$HOST/.llm-wiki-adopt-log.md'"

# Host content survives across all three.
assert "CLAUDE.md preserves host's title" \
    "grep -qFx '# Defaults With Host Content' '$HOST/CLAUDE.md'"
assert "CLAUDE.md gained NO sentinel blocks (never touched anymore)" \
    "! grep -qF '<!-- lw:' '$HOST/CLAUDE.md'"
assert ".claude/rules/wiki-as-memory.md was ADDed (instructions via rules)" \
    "[ -f '$HOST/.claude/rules/wiki-as-memory.md' ]"
assert ".gitignore preserves host's *.npz rule" \
    "grep -qFx '*.npz' '$HOST/.gitignore'"
assert ".gitignore did NOT gain the wiki/*.wiki/ rule (host file untouched)" \
    "! grep -qF 'wiki/*.wiki/' '$HOST/.gitignore'"
assert "wiki/.gitignore was ADDed with the *.wiki/ rule" \
    "grep -qFx '*.wiki/' '$HOST/wiki/.gitignore'"
assert ".claude/settings.json preserves host's theme=host" \
    "grep -qF '\"theme\": \"host\"' '$HOST/.claude/settings.json'"
assert ".claude/settings.json preserves host's permissions.allow.Bash" \
    "grep -qF 'Bash' '$HOST/.claude/settings.json'"
assert ".claude/settings.json gained the SessionStart hook" \
    "grep -qF 'SessionStart' '$HOST/.claude/settings.json'"
