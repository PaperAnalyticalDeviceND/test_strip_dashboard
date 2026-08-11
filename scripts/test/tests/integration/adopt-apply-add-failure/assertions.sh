#!/usr/bin/env bash
# Assertions: when a destination path under an ADD entry is blocked by
# a non-directory in the host, cp -p / mkdir -p fail. Adopt must
# capture the RC, record the failing paths under ADD FAILED in the
# manifest, and NOT count them under APPLIED_ADDS.

STAGE="$SANDBOX/adopt-apply-add-failure"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
RC_FILE="$STAGE/rc.txt"

assert "apply produced output" "[ -f '$OUT' ]"

# Manifest written (the FAILED_ADDS code path must not crash the run).
assert "manifest exists (failures are captured, not crashes)" \
    "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"

# The blocker files survived (proves they really blocked).
assert "host's wiki/agents/claude-code blocker file is still a regular file" \
    "[ -f '$HOST/wiki/agents/claude-code' ] && [ ! -d '$HOST/wiki/agents/claude-code' ]"
assert "host's scripts/lib blocker file is still a regular file" \
    "[ -f '$HOST/scripts/lib' ] && [ ! -d '$HOST/scripts/lib' ]"

# Files under the blockers were NOT created (since the blocker is a file).
assert "blocked path wiki/agents/claude-code/setup.sh was NOT created" \
    "[ ! -e '$HOST/wiki/agents/claude-code/setup.sh' ]"
assert "blocked path scripts/lib/common.sh was NOT created" \
    "[ ! -e '$HOST/scripts/lib/common.sh' ]"

# Manifest reports the failures in a dedicated block.
assert "manifest has ADD FAILED block with non-zero count" \
    "grep -qE '^- ADD FAILED \\([1-9][0-9]* files' '$HOST/.llm-wiki-adopt-log.md'"
# Scope these to the ADD FAILED block only (between '- ADD FAILED' header
# and the next top-level '-' header); without scoping, an unfixed run
# still has the blocked paths listed under '- ADDed (...)' and these
# greps would pass against the wrong block.
assert "ADD FAILED block (scoped) lists wiki/agents/claude-code/setup.sh" \
    "awk '/^- ADD FAILED/,/^- SKIPped/' '$HOST/.llm-wiki-adopt-log.md' | grep -qF -- '- wiki/agents/claude-code/setup.sh'"
assert "ADD FAILED block (scoped) lists scripts/lib/common.sh" \
    "awk '/^- ADD FAILED/,/^- SKIPped/' '$HOST/.llm-wiki-adopt-log.md' | grep -qF -- '- scripts/lib/common.sh'"
# Corollary: the same paths must NOT appear in the ADDed block.
assert "ADDed block does NOT claim the blocked paths as applied" \
    "! awk '/^- ADDed/,/^- ADD FAILED/' '$HOST/.llm-wiki-adopt-log.md' | grep -qF -- '- wiki/agents/claude-code/setup.sh'"

# The succeeding ADD entries are still recorded.
assert "manifest ADDed block lists llm-wiki.md (unblocked path succeeded)" \
    "awk '/^- ADDed/,/^- ADD FAILED|^- SKIPped/' '$HOST/.llm-wiki-adopt-log.md' | grep -qF -- '- llm-wiki.md'"

# Summary line on stdout calls out the failures.
assert "stdout summary mentions FAILED count" \
    "grep -qE 'Applied: [0-9]+ file\\(s\\) created, [1-9][0-9]* FAILED' '$OUT'"
