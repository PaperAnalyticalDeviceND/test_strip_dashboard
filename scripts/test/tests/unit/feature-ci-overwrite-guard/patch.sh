#!/usr/bin/env bash
# Patch: two tmp project roots for the CI-workflow overwrite guard (issue #68).
#
#   collision/  has a PRE-EXISTING host-owned .github/workflows/test-feature.yml
#               whose basename collides with the fixture feature's ci.workflow_file.
#               install_feature must refuse and leave the host file untouched.
#   clean/      has no colliding workflow. The control: the guard must not
#               break the normal install path.
#
# Inputs:  SANDBOX env var (from run.sh) pointing at the sandbox root.

set -uo pipefail

HERE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_SRC="$HERE_DIR/../../../_fixtures/test-feature"

if [[ ! -d "$FIXTURE_SRC" ]]; then
    echo "  ERROR: fixture not found at $FIXTURE_SRC" >&2
    exit 1
fi

STAGE="$SANDBOX/feature-ci-overwrite-guard"

for proj in collision clean; do
    PROJ="$STAGE/$proj"
    mkdir -p "$PROJ/_fixtures"
    cp -R "$FIXTURE_SRC" "$PROJ/_fixtures/"
    cat > "$PROJ/CLAUDE.md" <<'EOF'
# Test Project

Baseline CLAUDE.md for the CI overwrite guard test.
EOF
done

# The collision: a host-owned workflow at the exact destination install_feature
# derives (basename of the feature's ci.workflow_file). Distinctive marker
# content so the assertions can tell host bytes from feature bytes.
mkdir -p "$STAGE/collision/.github/workflows"
cat > "$STAGE/collision/.github/workflows/test-feature.yml" <<'EOF'
# HOST-OWNED-WORKFLOW-MARKER: this file predates the feature and must survive.
name: host-ci
on: [push]
jobs:
  host-job:
    runs-on: ubuntu-latest
    steps:
      - run: echo "host workflow, not the feature's"
EOF

echo "  feature-ci-overwrite-guard patch applied: projects at $STAGE/{collision,clean}"
