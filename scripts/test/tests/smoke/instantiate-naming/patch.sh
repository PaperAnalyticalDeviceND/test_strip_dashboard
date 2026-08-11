#!/usr/bin/env bash
# Smoke test: instantiate derives the project name from the origin remote,
# not the clone-directory basename (F1, chunk 03).
#
# Stages a template clone in a directory deliberately named 'clonedir', points
# its origin at .../widget.git, and runs instantiate.sh --agent=none. The
# generated wiki and namespaced files must use 'widget' (from origin), proving
# instantiate resolves the name once via lw_name_from_origin and hands it to
# init-wiki.sh through --repo-name.
#
# Inputs:  SANDBOX env var. lib/template.sh's clone_template.
# Effects: $SANDBOX/instantiate-naming/clonedir bootstrapped with origin=widget.
#
# Hermetic after clone: --agent=none plus local wiki init contact no network;
# the origin remote is only parsed for its name, never fetched.

set -euo pipefail

HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

STAGE="$SANDBOX/instantiate-naming"
T="$STAGE/clonedir"
mkdir -p "$STAGE"

if [ -d "$T" ]; then
    echo "  instantiate-naming already staged at $T (idempotent re-run)."
elif clone_template "$T"; then
    echo "  Cloned template to $T."
else
    echo "  Smoke instantiate-naming assertions will skip (no template available)." >&2
    exit 0
fi

# Point origin at a repo whose name (widget) differs from the basename
# (clonedir). clone_template leaves origin set (network mode) or unset
# (local mode); normalize to the divergent URL either way.
git -C "$T" remote remove origin 2>/dev/null || true
git -C "$T" remote add origin "https://github.com/acme/widget.git"

if [ -f "$T/scripts/instantiate.sh" ]; then
    (
        cd "$T"
        rc=0
        bash scripts/instantiate.sh "Widget Project" \
            --agent=none \
            --description="F1 naming handshake smoke test." \
            >/tmp/instantiate-naming.log 2>&1 || rc=$?
        # rc sidecar outside the tree; assertions.sh asserts rc == 0
        # (a WARN alone let mid-run instantiate deaths pass silently).
        echo "$rc" > "$T.instantiate-rc"
        if [ "$rc" -ne 0 ]; then
            echo "  WARN: instantiate.sh failed (rc=$rc); the exit-status assertion will fail." >&2
            sed 's/^/    /' /tmp/instantiate-naming.log >&2
        fi
    )
fi

echo "  Smoke instantiate-naming patch applied: template at $T."
