#!/usr/bin/env bash
# Smoke test: instantiate.sh with --features=agent-comms.
#
# Verifies the --features= integration with our agent-comms feature
# end-to-end: a fresh template gets bootstrapped AND our feature gets
# installed in one shot via the same path a real user would take.
#
# Because the upstream template doesn't yet ship features/agent-comms/
# (we haven't PR'd it yet, per the Path-B Build-First strategy), we
# clone the template and INJECT our local features/agent-comms/ into
# the cloned template's features/ directory before running
# instantiate.sh. That lets the test exercise the real instantiate.sh
# --features= integration against the in-development feature.
#
# Inputs:  SANDBOX env var. lib/template.sh's clone_template.
# Effects: $SANDBOX/template-comms/ contains a derivative bootstrapped
#          with --agent=none --features=agent-comms.

set -euo pipefail

HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

# Locate this derived repo's features/agent-comms/ (for injection).
HERE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_REPO_ROOT="$(cd "$HERE_DIR/../../../../.." && pwd)"
LOCAL_FEATURE_DIR="$DERIVED_REPO_ROOT/features/agent-comms"

if [ ! -d "$LOCAL_FEATURE_DIR" ]; then
    echo "  ERROR: local features/agent-comms/ not found at $LOCAL_FEATURE_DIR" >&2
    echo "         Cannot inject the feature into the cloned template." >&2
    exit 1
fi

T="$SANDBOX/template-comms"

if [ -d "$T" ]; then
    echo "  template-comms already cloned at $T (idempotent re-run)."
elif clone_template "$T"; then
    echo "  Cloned template to $T."
else
    echo "  Smoke instantiate-with-agent-comms assertions will skip" >&2
    echo "  (template not cloned: no network and no MVP_TEMPLATE_LOCAL," >&2
    echo "   or MVP_TEMPLATE_LOCAL points at a derived project per issue #15)." >&2
    exit 0
fi

# Point origin at a derived-style URL so REPO_NAME resolves to template-comms
# (not the upstream template's own name, llm-wiki-memory-template). After F1
# was fixed in #42, instantiate.sh derives REPO_NAME from origin via
# lw_name_from_origin; the smoke wiki-path assertions assume REPO_NAME =
# basename($T). Same approach as scripts/test/tests/smoke/instantiate-naming/.
git -C "$T" remote remove origin 2>/dev/null || true
git -C "$T" remote add origin "https://github.com/test-user/template-comms.git"

# Inject our local feature into the cloned template's features/ directory.
# Idempotent: only copy if not already there from a prior run.
if [ ! -d "$T/features/agent-comms" ]; then
    mkdir -p "$T/features"
    cp -R "$LOCAL_FEATURE_DIR" "$T/features/agent-comms"
    echo "  Injected features/agent-comms/ into the cloned template."
else
    echo "  features/agent-comms/ already present in cloned template."
fi

# Run instantiate.sh with --features=agent-comms. Guard: only if
# instantiate.sh is still present (it self-deletes on success).
if [ -f "$T/scripts/instantiate.sh" ]; then
    (
        cd "$T"
        rc=0
        bash scripts/instantiate.sh "Agent Comms Smoke Test" \
            --agent=none \
            --description="Smoke test for instantiate.sh --features=agent-comms" \
            --features=agent-comms \
            >/tmp/instantiate-with-agent-comms.log 2>&1 || rc=$?
        # rc sidecar outside the tree; assertions.sh asserts rc == 0
        # (a WARN alone let mid-run instantiate deaths pass silently).
        echo "$rc" > "$T.instantiate-rc"
        if [ "$rc" -ne 0 ]; then
            echo "  WARN: instantiate.sh --features=agent-comms failed (rc=$rc); the exit-status assertion will fail." >&2
            sed 's/^/    /' < /tmp/instantiate-with-agent-comms.log >&2
        fi
    )
fi

echo "  instantiate-with-agent-comms patch applied: template at $T."
