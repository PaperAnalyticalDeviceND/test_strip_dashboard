#!/usr/bin/env bash
# Patch: set up tmp project roots inside the sandbox so install_feature can
# find the test-feature fixture via FEATURES_DIR.
#
# Inputs:  SANDBOX env var (from run.sh) pointing at the sandbox root.
# Effects:
#   - Creates $SANDBOX/feature-flag-test-project/ with CLAUDE.md (plus a
#     .baseline snapshot to prove the install never touches it), a
#     .claude/rules/ directory holding a pre-existing sibling rule
#     (keep-me.md, also snapshotted) to prove uninstall is file-scoped,
#     and a parallel _fixtures/ directory.
#   - Creates $SANDBOX/feature-flag-noclaude-project/ with CLAUDE.md but
#     NO .claude/ directory, for the rule-install gate branch.

set -uo pipefail

PROJ="$SANDBOX/feature-flag-test-project"
NOCLAUDE_PROJ="$SANDBOX/feature-flag-noclaude-project"
# patch.sh is invoked (not sourced), so compute the fixture path from this
# file's own location. Layout: <test>/tests/unit/feature-flag-infra/patch.sh
# -> fixture at <test>/_fixtures/test-feature
HERE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_SRC="$HERE_DIR/../../../_fixtures/test-feature"

if [[ ! -d "$FIXTURE_SRC" ]]; then
    echo "  ERROR: fixture not found at $FIXTURE_SRC" >&2
    exit 1
fi

mkdir -p "$PROJ/_fixtures"
cp -R "$FIXTURE_SRC" "$PROJ/_fixtures/"

# Baseline CLAUDE.md (small but realistic; the install must never touch it)
cat > "$PROJ/CLAUDE.md" <<'EOF'
# Test Project

> Baseline CLAUDE.md for feature-flag infra testing.

## Notes

Pre-existing content that must be preserved across install + uninstall.
EOF

# Snapshot the baseline so the untouched/identity assertions can compare
cp "$PROJ/CLAUDE.md" "$PROJ/CLAUDE.md.baseline"

# Pre-existing sibling rule: uninstall must remove only the feature's own
# rule file, leaving this one (and the directory) in place.
mkdir -p "$PROJ/.claude/rules"
cat > "$PROJ/.claude/rules/keep-me.md" <<'EOF'
# Keep me

Host-owned rule that install/uninstall must leave untouched.
EOF
cp "$PROJ/.claude/rules/keep-me.md" "$PROJ/keep-me.md.baseline"

# Second project without .claude/: the rule install must skip loudly and
# must NOT create the directory.
mkdir -p "$NOCLAUDE_PROJ/_fixtures"
cp -R "$FIXTURE_SRC" "$NOCLAUDE_PROJ/_fixtures/"
cat > "$NOCLAUDE_PROJ/CLAUDE.md" <<'EOF'
# No-Claude Project

Host CLAUDE.md; there is deliberately no .claude/ directory here.
EOF

echo "  feature-flag-infra patch applied: project roots at $PROJ and $NOCLAUDE_PROJ"
