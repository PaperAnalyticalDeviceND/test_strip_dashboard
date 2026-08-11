#!/usr/bin/env bash
# Patch: set up a tmp project root inside the sandbox with a baseline
# CLAUDE.md, ready for the assertions to install/uninstall the REAL
# features/agent-comms/ via FEATURES_DIR pointing at this repo's
# features/ directory.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects:
#   - Creates $SANDBOX/agent-comms-test-project/ with CLAUDE.md and
#     CLAUDE.md.baseline (snapshot for byte-equivalence check after
#     install + uninstall).

set -uo pipefail

PROJ="$SANDBOX/agent-comms-test-project"

# Locate the repo root from this file's path:
# <repo>/scripts/test/tests/unit/agent-comms-feature-install/patch.sh
HERE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE_DIR/../../../../.." && pwd)"
FEATURE_DIR="$REPO_ROOT/features/agent-comms"

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "  ERROR: features/agent-comms not found at $FEATURE_DIR" >&2
    exit 1
fi
if [[ ! -f "$FEATURE_DIR/feature.json" ]]; then
    echo "  ERROR: $FEATURE_DIR/feature.json missing" >&2
    exit 1
fi

mkdir -p "$PROJ"

# Baseline CLAUDE.md: realistic, with content the install must preserve.
cat > "$PROJ/CLAUDE.md" <<'EOF'
# Test Project

> Baseline CLAUDE.md for agent-comms feature install testing.

## Notes

Pre-existing content that must be preserved across install + uninstall.
EOF

# Snapshot the baseline so the byte-equivalence assertion can compare.
cp "$PROJ/CLAUDE.md" "$PROJ/CLAUDE.md.baseline"

# .claude/ exists but .claude/rules/ does not: install must create the
# rules directory, uninstall must remove it again once empty.
mkdir -p "$PROJ/.claude"

echo "  agent-comms-feature-install patch applied: project root at $PROJ"
