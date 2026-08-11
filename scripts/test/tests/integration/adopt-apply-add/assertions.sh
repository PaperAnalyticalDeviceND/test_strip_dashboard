#!/usr/bin/env bash
# Assertions: adopt.sh --apply (Phase 1: ADD only) writes ADD entries to
# the host tree, creates parent directories, leaves SKIP/REFUSE alone,
# writes the manifest .llm-wiki-adopt-log.md, and is idempotent at the
# file level on a clean re-run.

STAGE="$SANDBOX/adopt-apply-add"
HOST="$STAGE/host"
OUT1="$STAGE/apply-run1.txt"
OUT2="$STAGE/apply-run2.txt"
# Compute the template root from the harness location ($HERE = scripts/test/).
# Used to compare 'host file is byte-equal to template' and to re-invoke
# adopt.sh for the dirty-tree guard test below.
TEMPLATE_ROOT_AA="$(cd "$HERE/../.." && pwd)"

# --- Output captured ---
assert "first --apply produced an output file" "[ -f '$OUT1' ]"
assert "first --apply banner says --apply (not --dry-run)" \
    "grep -qF 'adopt.sh --apply' '$OUT1'"
assert "first --apply does NOT say 'Dry-run only'" \
    "! grep -qF 'Dry-run only.' '$OUT1'"

# --- ADD entries actually written to host ---
assert "ADD: wiki/init-wiki.sh created in host" \
    "[ -f '$HOST/wiki/init-wiki.sh' ]"
assert "ADD: scripts/lib/common.sh created in host" \
    "[ -f '$HOST/scripts/lib/common.sh' ]"
assert "ADD: scripts/update-from-template.sh created in host" \
    "[ -f '$HOST/scripts/update-from-template.sh' ]"
# Parent directory was non-existent before; cp + mkdir -p must have created it.
assert "ADD: scripts/lib/ directory created (mkdir -p worked)" \
    "[ -d '$HOST/scripts/lib' ]"

# Skills (directory-per-skill layout). Without these on disk,
# /wiki-experiment etc. fail at runtime. PR #51 item #2. Each SKILL.md
# lives one directory deeper than the old flat files, so these also
# exercise adopt's mkdir -p on a two-level path.
assert "ADD: .claude/skills/wiki-experiment/SKILL.md created in host" \
    "[ -f '$HOST/.claude/skills/wiki-experiment/SKILL.md' ]"
assert "ADD: .claude/skills/wiki-source/SKILL.md created in host" \
    "[ -f '$HOST/.claude/skills/wiki-source/SKILL.md' ]"
assert "ADD: .claude/skills/wiki-lint/SKILL.md created in host" \
    "[ -f '$HOST/.claude/skills/wiki-lint/SKILL.md' ]"
assert "ADD: copied SKILL.md is byte-equal to template" \
    "cmp -s '$TEMPLATE_ROOT_AA/.claude/skills/wiki-lint/SKILL.md' '$HOST/.claude/skills/wiki-lint/SKILL.md'"
# The retired flat/commands layout must NOT come back: the manifest is the
# only source of these paths, so their absence proves the old entries are
# gone rather than merely renamed alongside. /ask still ships as a command
# (no skill twin; the retirement targets wiki-* duplicates only), so assert
# the retired files individually rather than the directory's absence.
assert "ADD: no flat .claude/skills/wiki-lint.md created" \
    "[ ! -f '$HOST/.claude/skills/wiki-lint.md' ]"
assert "ADD: no .claude/commands/wiki-*.md duplicates created" \
    "[ ! -f '$HOST/.claude/commands/wiki-experiment.md' ] && [ ! -f '$HOST/.claude/commands/wiki-source.md' ] && [ ! -f '$HOST/.claude/commands/wiki-lint.md' ]"
assert "ADD: .claude/commands/ask.md created in host" \
    "[ -f '$HOST/.claude/commands/ask.md' ]"

# Rule files: Claude Code auto-discovers .claude/rules/*.md, so landing on
# disk is the whole installation. They are name-agnostic by contract
# (manifest-shape enforces it), so the verbatim cp -p copy is also correct.
assert "ADD: .claude/rules/wiki-as-memory.md created in host" \
    "[ -f '$HOST/.claude/rules/wiki-as-memory.md' ]"
assert "ADD: .claude/rules/memory-boundary.md created in host" \
    "[ -f '$HOST/.claude/rules/memory-boundary.md' ]"
assert "ADD: copied wiki-as-memory rule is byte-equal to template" \
    "cmp -s '$TEMPLATE_ROOT_AA/.claude/rules/wiki-as-memory.md' '$HOST/.claude/rules/wiki-as-memory.md'"

# Byte-equal to template (cp -p preserves content/perms).
assert "ADD: copied wiki/init-wiki.sh is byte-equal to template" \
    "cmp -s '$TEMPLATE_ROOT_AA/wiki/init-wiki.sh' '$HOST/wiki/init-wiki.sh'"

# --- SKIP and REFUSE: host's prior state preserved ---
assert "SKIP: llm-wiki.md left untouched (was byte-equal already)" \
    "cmp -s '$TEMPLATE_ROOT_AA/llm-wiki.md' '$HOST/llm-wiki.md'"
assert "REFUSE: host's wiki/agents/discipline-gates.md NOT overwritten" \
    "grep -qF 'Host-modified discipline-gates' '$HOST/wiki/agents/discipline-gates.md'"

# --- Adoption manifest written ---
assert "manifest .llm-wiki-adopt-log.md exists" \
    "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest has the top-level heading" \
    "grep -qF '# llm-wiki adopt log' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest names this run as 'adopt --apply (phases 1, 2B, 3)'" \
    "grep -qF 'adopt --apply (phases 1, 2B, 3)' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records project name" \
    "grep -qF -- '- project: apply-host' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records the signal count" \
    "grep -qE -- '- signals matched: [0-9]+ of 3' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest lists each ADDed path under the ADDed bullet" \
    "grep -qF -- '  - wiki/init-wiki.sh' '$HOST/.llm-wiki-adopt-log.md'"

# --- Apply-phase statuses + the one remaining deferral (feature install) ---
assert "manifest records init-wiki status" \
    "grep -qE -- '- init-wiki: (applied|already-present|skipped)' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records overlay setup status" \
    "grep -qE -- '- overlay setup: (applied|skipped)' '$HOST/.llm-wiki-adopt-log.md'"
assert "NOT IMPLEMENTED YET still names feature install as deferred" \
    "grep -qF 'Feature install via --features' '$OUT1'"

# --- Second run with --force: still idempotent at the file level ---
assert "second --apply --force produced an output file" "[ -f '$OUT2' ]"
assert "second --apply --force reports 0 files created" \
    "grep -qE 'Applied: 0 file' '$OUT2'"

# --- Third run without --force: advisory abort fires ---
OUT3="$STAGE/apply-run3-noforce.txt"
NOFORCE_RC_FILE="$STAGE/noforce-rc.txt"
assert "third --apply without --force exits non-zero" \
    "[ \"\$(cat '$NOFORCE_RC_FILE')\" != 0 ]"
assert "third --apply without --force prints the advisory" \
    "grep -qF 'this repo has already adopted' '$OUT3'"
assert "third --apply without --force routes user to update-from-template.sh" \
    "grep -qF 'bash scripts/update-from-template.sh' '$OUT3'"
assert "third --apply without --force mentions --force as the escape hatch" \
    "grep -qF -- '--force' '$OUT3'"

# Manifest grew by exactly one entry per run that wrote it. First run wrote,
# second run --force wrote, third run aborted before manifest write.
manifest_entries=$(grep -cE '^## \[.*\] adopt --apply' "$HOST/.llm-wiki-adopt-log.md" || true)
assert "manifest has two entries (first run + second --force; third aborted)" \
    "[ '$manifest_entries' -eq 2 ]"

# --- Dirty tree guard: simulate a dirty tree and confirm --apply refuses ---
echo "uncommitted edit" >> "$HOST/README.md"
DIRTY_OUT=$(mktemp)
DIRTY_RC=0
bash "$TEMPLATE_ROOT_AA/scripts/adopt.sh" --target="$HOST" --apply > "$DIRTY_OUT" 2>&1 || DIRTY_RC=$?
assert "dirty tree: --apply exits non-zero" "[ '$DIRTY_RC' -ne 0 ]"
assert "dirty tree: error message mentions uncommitted changes" \
    "grep -qF 'uncommitted changes' '$DIRTY_OUT'"
rm -f "$DIRTY_OUT"
# Restore clean state for any later assertions (not strictly needed; harness
# tears the sandbox down).
git -C "$HOST" checkout README.md 2>/dev/null || true
