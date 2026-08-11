#!/usr/bin/env bash
#
# Claude Code SessionStart hook: surfaces this project's wiki at the
# start of every session so the agent treats the wiki as compounding
# memory rather than as on-demand RAG.
#
# Three blocks of output, all going to stdout (captured by Claude Code as
# a system-reminder at the start of the session):
#
#   1. Orientation reminder. Tells the agent the wiki exists, where it
#      lives, the read/write loop, and the commit discipline. Constant
#      text; safe even if the wiki sub-repo is absent.
#
#   2. The wiki's index page. Catalog of every page in the wiki, with
#      one-line descriptions. The intent of model_fusion recommendation
#      #1: with the index in context at turn 0, the agent answers wiki-
#      pageable questions without an extra Read/Grep tool call. The wiki
#      becomes memory, not search.
#
#   3. The last 5 log entries. Recent activity gives the agent enough
#      continuity from prior sessions to pick up mid-thread.
#
# Blocks 2 and 3 are skipped silently if the wiki sub-repo has not been
# initialised yet, so the hook is safe to install before init-wiki.sh
# runs. The cost is a few thousand tokens at session start, paid once,
# in exchange for the wiki actually functioning as memory.
#
# Installed by wiki/agents/claude-code/setup.sh --hook into
# .claude/hooks/session-start.sh, with test_strip_dashboard substituted at
# install time. Also installed by scripts/instantiate.sh --dev-self for
# template-contributor self-dogfooding.
#

# Block 1: orientation reminder (always emitted).
cat <<'EOF'
<system-reminder>
This project uses the wiki at wiki/test_strip_dashboard.wiki/ as durable memory.
It is a separate git repository with its own remote, NOT a subdirectory of
the main repo. Read SCHEMA_test_strip_dashboard.md before non-trivial wiki edits.
Update the wiki proactively when experiment results, decisions, or
syntheses emerge.

Every wiki edit ends with a commit in the wiki's own repo:
  git -C wiki/test_strip_dashboard.wiki add <files>
  git -C wiki/test_strip_dashboard.wiki commit -m "..."
Run these without asking — local commits are reversible. Push only on
explicit request.

Slash commands available: /wiki-experiment, /wiki-source, /wiki-lint.
</system-reminder>
EOF

# Block 2: wiki index, if the wiki sub-repo exists.
INDEX_FILE="wiki/test_strip_dashboard.wiki/index_test_strip_dashboard.md"
if [[ -f "$INDEX_FILE" ]]; then
    echo
    echo "<system-reminder>"
    echo "## Wiki current state — index"
    echo
    cat "$INDEX_FILE"
    echo "</system-reminder>"
fi

# Block 3: last 5 log entries, if the log exists. The log is append-only
# with newest at the bottom, so "last 5" means the 5 most recent.
LOG_FILE="wiki/test_strip_dashboard.wiki/log_test_strip_dashboard.md"
if [[ -f "$LOG_FILE" ]]; then
    TOTAL_ENTRIES=$(grep -c '^## \[' "$LOG_FILE" 2>/dev/null || echo 0)
    START_ENTRY=1
    if [[ "$TOTAL_ENTRIES" -gt 5 ]]; then
        START_ENTRY=$((TOTAL_ENTRIES - 4))
    fi
    echo
    echo "<system-reminder>"
    echo "## Wiki current state — last 5 log entries"
    echo
    awk -v s="$START_ENTRY" '/^## \[/{c++} c>=s' "$LOG_FILE"
    echo "</system-reminder>"
fi
