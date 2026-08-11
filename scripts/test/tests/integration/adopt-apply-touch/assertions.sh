#!/usr/bin/env bash
# Assertions: adopt.sh --apply applies the merge TOUCH grant via the
# overlay setup.sh --hook; the host's .gitignore and CLAUDE.md are never
# modified (the wiki ignore rule arrives as the ADDed wiki/.gitignore,
# the behavioral instructions as the ADDed .claude/rules/*.md); manifest
# records the TOUCH apply.

STAGE="$SANDBOX/adopt-apply-touch"
HOST="$STAGE/host"
OUT1="$STAGE/apply-run1.txt"
OUT2="$STAGE/apply-run2.txt"

# --- First run produced output ---
assert "first --apply produced output" "[ -f '$OUT1' ]"

# --- Host .gitignore untouched; wiki ignore rule arrived via ADD ---
assert "host .gitignore is byte-identical to its pre-adopt snapshot" \
    "cmp -s '$STAGE/gitignore.before' '$HOST/.gitignore'"
assert "wiki/.gitignore was ADDed to the host" \
    "[ -f '$HOST/wiki/.gitignore' ]"
assert "wiki/.gitignore carries the *.wiki/ rule" \
    "grep -qFx '*.wiki/' '$HOST/wiki/.gitignore'"
assert "git ignores the wiki sub-repo via wiki/.gitignore" \
    "git -C '$HOST' check-ignore -q wiki/touch-host.wiki/"

# --- Manifest records the apply outcomes ---
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest does NOT list a .gitignore TOUCH (no such grant anymore)" \
    "! grep -qF -- '- .gitignore (' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT list a CLAUDE.md TOUCH (managed-block grant retired)" \
    "! grep -qF -- '- CLAUDE.md (' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports settings.json merge as applied via setup.sh --hook" \
    "grep -qF '.claude/settings.json (merge): applied via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md'"
# Guard against the false-positive that the previous version of this test
# allowed: a 'failed' entry in any manifest run would prove the assertion
# above is insufficient on its own (the grep only requires the 'applied'
# string to appear once across the whole manifest).
assert "manifest does NOT report settings.json merge as failed in any run" \
    "! grep -qF '.claude/settings.json (merge): failed' '$HOST/.llm-wiki-adopt-log.md'"

# --- Phase 3: settings.json now has the SessionStart hook (via jq merge) ---
assert "host .claude/settings.json now references session-start.sh" \
    "grep -qF 'session-start.sh' '$HOST/.claude/settings.json'"
assert "host's own 'permissions.allow.Bash' key survived the merge" \
    "grep -qF 'Bash' '$HOST/.claude/settings.json'"

# --- Phase 2B: init-wiki + overlay setup status in manifest ---
assert "manifest records init-wiki as applied on first run" \
    "grep -qF -- '- init-wiki: applied' '$STAGE/apply-run1.txt' || \\
     grep -qF -- '- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records init-wiki as already-present on second run" \
    "grep -qF -- '- init-wiki: already-present' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records overlay setup status as applied" \
    "grep -qF -- '- overlay setup: applied' '$HOST/.llm-wiki-adopt-log.md'"

# --- Phase 2B: wiki sub-repo created in host ---
assert "wiki sub-repo created at wiki/touch-host.wiki/" \
    "[ -d '$HOST/wiki/touch-host.wiki/.git' ]"

# --- CLAUDE.md untouched; the instructions arrived as ADDed rule files ---
assert "host CLAUDE.md is byte-identical to its pre-adopt snapshot" \
    "cmp -s '$STAGE/claude-md.before' '$HOST/CLAUDE.md'"
assert "host CLAUDE.md gained NO lw sentinels" \
    "! grep -qF '<!-- lw:' '$HOST/CLAUDE.md'"
assert ".claude/rules/wiki-as-memory.md was ADDed to the host" \
    "[ -f '$HOST/.claude/rules/wiki-as-memory.md' ]"
assert ".claude/rules/memory-boundary.md was ADDed to the host" \
    "[ -f '$HOST/.claude/rules/memory-boundary.md' ]"
assert "host README preserved" \
    "grep -qF 'Host-authored README' '$HOST/README.md'"

# --- Second run: idempotency ---
assert "second --apply produced output" "[ -f '$OUT2' ]"
assert "host .gitignore still byte-identical after the second --apply" \
    "cmp -s '$STAGE/gitignore.before' '$HOST/.gitignore'"
assert "host CLAUDE.md still byte-identical after the second --apply" \
    "cmp -s '$STAGE/claude-md.before' '$HOST/CLAUDE.md'"
