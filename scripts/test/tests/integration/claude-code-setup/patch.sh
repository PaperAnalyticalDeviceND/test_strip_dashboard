#!/usr/bin/env bash
# Patch: stage fixtures for the claude-code-setup integration test.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/claude-code-setup/ with:
#   checkout/  git repo whose basename ('checkout') deliberately differs
#              from its wiki name ('sigil'), to prove setup.sh takes the
#              name from the on-disk wiki, not the clone directory.
#   nowiki/    git repo with no wiki/*.wiki (exercises the fail-loud path).
#   merge/     git repo with a pre-existing session-start hook and a
#              settings.json lacking that hook, so --hook's only change is
#              the jq merge (the audit #9 "merged-only" regression case).
#   cfg/       used as CLAUDE_CONFIG_DIR so --seed-memory stays in the
#              sandbox instead of touching the real ~/.claude.

set -uo pipefail

STAGE="$SANDBOX/claude-code-setup"
mkdir -p "$STAGE/cfg"

# setup.sh reads its overlay templates from $REPO_ROOT; copy the real ones
# into each fixture. patch.sh is executed, so locate the checkout from this
# file's own path (tests/integration/<name> -> five levels up). NOT git
# rev-parse: in a nested worktree/workspace without its own .git, rev-parse
# walks up to the OUTER checkout and stages stale fixtures from there,
# while assertions.sh runs the inner checkout's scripts — a mixed-root test.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
TPL_SRC="$REPO_ROOT/wiki/agents/claude-code/templates"

# $1=project dir, $2=wiki name ('' = create no wiki)
_mkproj() {
    local dir="$1" wn="$2"
    git init -q "$dir"
    git -C "$dir" config user.email "cc-test@example.test"
    git -C "$dir" config user.name  "cc test"
    mkdir -p "$dir/wiki/agents/claude-code"
    cp -R "$TPL_SRC" "$dir/wiki/agents/claude-code/templates"
    if [ -n "$wn" ]; then
        mkdir -p "$dir/wiki/$wn.wiki"
        : > "$dir/wiki/$wn.wiki/SCHEMA_$wn.md"
    fi
    # Host-authored CLAUDE.md. setup.sh must not modify it; the assertions
    # prove base mode leaves it alone.
    cat > "$dir/CLAUDE.md" <<'EOF'
# Project

Baseline content that must be preserved.
EOF
}

_mkproj "$STAGE/checkout" "sigil"
_mkproj "$STAGE/nowiki" ""

_mkproj "$STAGE/merge" "m"
mkdir -p "$STAGE/merge/.claude/hooks"
printf '#!/usr/bin/env bash\necho hi\n' > "$STAGE/merge/.claude/hooks/session-start.sh"
chmod +x "$STAGE/merge/.claude/hooks/session-start.sh"
printf '{ "other": true }\n' > "$STAGE/merge/.claude/settings.json"

echo "  claude-code-setup patch applied: fixtures at $STAGE"
