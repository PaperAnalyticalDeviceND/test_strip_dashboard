#!/usr/bin/env bash
# Patch: stage fixtures for the cursor-setup integration test.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/cursor-setup/ with:
#   checkout/  git repo whose basename ('checkout') deliberately differs
#              from its wiki name ('glyph'), to prove setup.sh takes the
#              name from the on-disk wiki, not the clone directory. Carries
#              the shipped .cursor/rules/*.mdc set and a host-owned
#              CLAUDE.md that setup.sh must never touch.
#   nowiki/    git repo with no wiki/*.wiki (exercises the fail-loud path).

set -uo pipefail

STAGE="$SANDBOX/cursor-setup"

# patch.sh is executed, so locate the checkout from this file's own path
# (tests/integration/cursor-setup -> five levels up). NOT git rev-parse:
# in a nested worktree/workspace without its own .git, rev-parse walks up
# to the OUTER checkout and stages stale fixtures from there, while
# assertions.sh runs the inner checkout's setup.sh — a mixed-root test.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"

# Template-checkout guard: the fixtures need .cursor/rules from the
# checkout, which instantiate prunes in derived projects (observed: 10
# spurious fails in a derived project's CI). Decline WITHOUT creating
# $STAGE so assertions.sh skips cleanly. Discriminator matches
# clone_template's issue-#15 guard.
if [ ! -f "$REPO_ROOT/scripts/instantiate.sh" ]; then
    echo "  cursor-setup: not a template checkout (derived project); declining to stage." >&2
    exit 0
fi
mkdir -p "$STAGE"
RULES_SRC="$REPO_ROOT/.cursor/rules"

# $1=project dir, $2=wiki name ('' = create no wiki)
_mkproj() {
    local dir="$1" wn="$2"
    git init -q "$dir"
    git -C "$dir" config user.email "cursor-test@example.test"
    git -C "$dir" config user.name  "cursor test"
    if [ -n "$wn" ]; then
        mkdir -p "$dir/wiki/$wn.wiki"
        : > "$dir/wiki/$wn.wiki/SCHEMA_$wn.md"
    fi
    # Host-owned CLAUDE.md. The overlay must leave it byte-identical;
    # assertions.sh snapshots it before running setup.sh.
    cat > "$dir/CLAUDE.md" <<'EOF'
# Project

Baseline content that must be preserved.
EOF
}

_mkproj "$STAGE/checkout" "glyph"
# Ship the .cursor/rules/*.mdc set so the rules check reports present.
mkdir -p "$STAGE/checkout/.cursor/rules"
cp "$RULES_SRC"/*.mdc "$STAGE/checkout/.cursor/rules/"

_mkproj "$STAGE/nowiki" ""

echo "  cursor-setup patch applied: fixtures at $STAGE"
