#!/usr/bin/env bash
# Assertions: with no .llm-wiki-adopt-grants.yml, adopt uses
# DEFAULT_GRANTS automatically. The one standard touch fires as if
# the host had hand-authored it; the host's preexisting .gitignore and
# CLAUDE.md survive untouched (the wiki ignore rule arrives as the ADDed
# wiki/.gitignore, the behavioral instructions as .claude/rules/*.md);
# and the dry-run/manifest are explicit about the source being defaults
# so the host can audit and override.

STAGE="$SANDBOX/adopt-apply-defaults-no-grants-file"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"

# Header is honest about the source of grants.
assert "header reports grants source as 'defaults', not 'not present'" \
    "grep -qE 'Grants file:\\s+defaults' '$OUT'"
assert "header surfaces the override mechanism in plain text" \
    "grep -qF 'commit one to override' '$OUT'"
assert "header does NOT call grants 'not present' (old behaviour)" \
    "! grep -qF 'Grants file:      not present' '$OUT'"

# TOUCH section lists exactly the one default target.
assert "TOUCH section lists 1 file (the one default)" \
    "grep -qF 'TOUCH (host-owned, granted' '$OUT' && \\
     grep -qF '1 files)' '$OUT'"
assert "TOUCH section does NOT list CLAUDE.md (grant retired)" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md'"
assert "TOUCH section does NOT list .gitignore (grant retired)" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.gitignore'"
assert "TOUCH section lists .claude/settings.json" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.claude/settings.json'"

# GRANT WARNINGS section absent (no INVALID grants in the defaults).
assert "GRANT WARNINGS section is not emitted (defaults are well-formed)" \
    "! grep -qF 'GRANT WARNINGS' '$OUT'"

# Integration touchpoints on disk.
assert "CLAUDE.md was NOT created (host-owned; adopt ships rules instead)" \
    "[ ! -f '$HOST/CLAUDE.md' ]"
assert ".claude/rules/wiki-as-memory.md was ADDed (instructions via rules)" \
    "[ -f '$HOST/.claude/rules/wiki-as-memory.md' ]"
assert "host .gitignore untouched (still only the host's own rule)" \
    "[ \"\$(cat '$HOST/.gitignore')\" = '*.pyc' ]"
assert "wiki/.gitignore was ADDed with the *.wiki/ rule" \
    "grep -qFx '*.wiki/' '$HOST/wiki/.gitignore'"
assert ".claude/settings.json was created" \
    "[ -f '$HOST/.claude/settings.json' ]"
assert ".claude/settings.json contains a SessionStart hook entry" \
    "grep -qF 'SessionStart' '$HOST/.claude/settings.json'"

# Manifest reports the touch with the right status strings.
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest does NOT list a CLAUDE.md TOUCH (managed-block grant retired)" \
    "! grep -qF -- '- CLAUDE.md (' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT list a .gitignore TOUCH (no such grant anymore)" \
    "! grep -qF -- '- .gitignore (' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest lists .claude/settings.json (merge): created from canonical via setup.sh --hook" \
    "grep -qF '.claude/settings.json (merge): created from canonical via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md'"

# Adopt did NOT create the .llm-wiki-adopt-grants.yml file (defaults
# are in-memory; the tool requesting permission does not mint it).
assert "adopt did NOT silently write .llm-wiki-adopt-grants.yml to the host" \
    "[ ! -f '$HOST/.llm-wiki-adopt-grants.yml' ]"
