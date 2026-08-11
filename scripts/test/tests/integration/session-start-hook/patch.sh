#!/usr/bin/env bash
# Integration test patch: SessionStart hook content injection.
#
# Stages two fake derived projects in the sandbox so assertions.sh can
# verify the hook's behaviour end to end:
#
#   $SANDBOX/session-start-hook/fakerepo/         — wiki sub-repo present
#       wiki/fakerepo.wiki/index_fakerepo.md      stub index
#       wiki/fakerepo.wiki/log_fakerepo.md        stub log with 7 entries
#       hook.sh                                   rendered hook (sed-substituted)
#
#   $SANDBOX/session-start-hook/fakerepo-nowiki/  — wiki sub-repo absent
#       hook.sh                                   rendered hook (sed-substituted)
#
# The hook is rendered via the same sed substitution that
# wiki/agents/claude-code/setup.sh applies at install time, so the test
# exercises the real install path's output. The assertions confirm the
# hook prints the orientation reminder, injects the index, emits the
# last 5 of 7 log entries (not the first 5), and gracefully skips the
# index/log blocks when the wiki sub-repo is absent.

set -euo pipefail

# Find the repo root regardless of harness CWD: the hook template lives
# there, not inside $SANDBOX. Resolved from this file's own path
# (tests/integration/<name> -> five levels up), NOT git rev-parse: in a
# nested worktree/workspace without its own .git, rev-parse walks up to
# the OUTER checkout and stages a stale template from there.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
HOOK_TEMPLATE="$REPO_ROOT/wiki/agents/claude-code/templates/session-start-hook.sh"

if [ ! -f "$HOOK_TEMPLATE" ]; then
    echo "  Hook template not found at $HOOK_TEMPLATE" >&2
    exit 1
fi

STAGE_DIR="$SANDBOX/session-start-hook"
mkdir -p "$STAGE_DIR"

# --- fakerepo: full wiki sub-repo with index + 7-entry log ---
FAKE_DIR="$STAGE_DIR/fakerepo"
WIKI_SUB="$FAKE_DIR/wiki/fakerepo.wiki"
mkdir -p "$WIKI_SUB"

# Stub index. Contains a sentinel phrase ("Index — fakerepo") that
# assertions.sh greps for to confirm the index made it into hook stdout.
cat > "$WIKI_SUB/index_fakerepo.md" <<'EOF'
---
type: index
up: "[[Home_fakerepo]]"
---

# Index — fakerepo

Catalog of all wiki pages.

## Overview
- [Home](Home_fakerepo) — Project summary

## Concepts
- [Test-Concept-Alpha](Test-Concept-Alpha) — sentinel page for index injection
EOF

# Stub log with 7 entries. The hook should emit entries 3 through 7
# (the last 5), skipping entries 1 and 2.
cat > "$WIKI_SUB/log_fakerepo.md" <<'EOF'
---
type: index
up: "[[Home_fakerepo]]"
---

# Log — fakerepo

Chronological record of wiki activity.

## [2026-01-01] create | Entry 1 — oldest, should NOT appear in hook output
- by: Test User via claude-code
- This is the oldest entry. With 7 entries total and last-5 logic, it gets skipped.

## [2026-01-02] ingest | Entry 2 — also too old, should NOT appear
- by: Test User via claude-code
- Second-oldest. Also skipped.

## [2026-02-01] ingest | Entry 3 — first of the last 5
- by: Test User via claude-code
- The hook output should START here.

## [2026-03-01] ingest | Entry 4
- by: Test User via claude-code
- Mid-range entry.

## [2026-04-01] lint | Entry 5
- by: Test User via claude-code
- Mid-range entry.

## [2026-05-01] ingest | Entry 6
- by: Test User via claude-code
- Mid-range entry.

## [2026-06-01] ingest | Entry 7 — most recent
- by: Test User via claude-code
- Newest entry, at the bottom of the file.
EOF

# Render the hook via the same sed pattern setup.sh uses, substituting
# REPO_NAME=fakerepo.
sed 's/\${REPO_NAME}/fakerepo/g' "$HOOK_TEMPLATE" > "$FAKE_DIR/hook.sh"
chmod +x "$FAKE_DIR/hook.sh"

# --- fakerepo-nowiki: render the same hook against a project with no
#     wiki sub-repo. The hook should still emit the orientation
#     reminder, but skip the index and log blocks silently. ---
NOWIKI_DIR="$STAGE_DIR/fakerepo-nowiki"
mkdir -p "$NOWIKI_DIR"
sed 's/\${REPO_NAME}/fakerepo-nowiki/g' "$HOOK_TEMPLATE" > "$NOWIKI_DIR/hook.sh"
chmod +x "$NOWIKI_DIR/hook.sh"

echo "  Session-start-hook patch staged: fakerepo (with wiki) + fakerepo-nowiki (without)."
