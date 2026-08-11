#!/usr/bin/env bash
# Patch: stage a fixture for the ensure-wiki SessionStart registration test.
#
# The hazard: when settings.json ALREADY has a SessionStart entry scoped to a
# narrow matcher (here, "resume"), the --hook merge must not fold the wiki
# hooks into that entry, or they inherit its matcher and never run on startup.
# This fixture pre-seeds exactly that shape so assertions.sh can verify the
# merge registers ensure-wiki on startup regardless.
#
# Inputs:  SANDBOX env var (from run.sh).
set -uo pipefail

STAGE="$SANDBOX/ensure-wiki-registration"
mkdir -p "$STAGE/cfg"

# Resolved from this file's own path (tests/integration/<name> -> five
# levels up), NOT git rev-parse: in a nested worktree/workspace without its
# own .git, rev-parse walks up to the OUTER checkout and stages stale
# fixtures from there.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
TPL_SRC="$REPO_ROOT/wiki/agents/claude-code/templates"

# A project whose wiki name is 'm'; templates copied in so setup.sh reads the
# real ones (mirrors the claude-code-setup fixture).
_mkproj() {
    local dir="$1" wn="$2"
    git init -q "$dir"
    git -C "$dir" config user.email "ew-test@example.test"
    git -C "$dir" config user.name  "ew test"
    mkdir -p "$dir/wiki/agents/claude-code"
    cp -R "$TPL_SRC" "$dir/wiki/agents/claude-code/templates"
    mkdir -p "$dir/wiki/$wn.wiki"
    : > "$dir/wiki/$wn.wiki/SCHEMA_$wn.md"
    cat > "$dir/CLAUDE.md" <<'EOF'
# Project

Baseline content that must be preserved.

### Knowledge Graph

KG section.
EOF
}

NARROW="$STAGE/narrow"
_mkproj "$NARROW" "m"
mkdir -p "$NARROW/.claude/hooks"

# Pre-existing settings.json: a SessionStart entry scoped to "resume" ONLY.
# A correct merge must register the wiki hooks so they still fire on startup.
cat > "$NARROW/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "resume",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/existing-resume-hook.sh" }
        ]
      }
    ]
  }
}
EOF

echo "  ensure-wiki-registration patch staged: narrow-matcher settings at $NARROW"
