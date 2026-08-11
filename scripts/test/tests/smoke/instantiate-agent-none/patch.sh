#!/usr/bin/env bash
# Smoke test: instantiate with --agent=none.
#
# Regression coverage for issue #9: instantiate.sh tripped `set -u` on
# bash 3.2 (macOS default) when INIT_AGENT_ARGS expanded empty for
# --agent=none, killing the bootstrap before init-wiki.sh could run.
#
# This test exercises the no-overlay path end-to-end so the bug cannot
# return silently. Runs against the macOS matrix where bash 3.2 actually
# reproduces the original failure.
#
# Inputs:  SANDBOX env var. lib/template.sh's clone_template.
# Effects: $SANDBOX/template-none/ contains a derivative bootstrapped
#          without any agent overlay.
#
# Idempotent.

set -euo pipefail

HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

T="$SANDBOX/template-none"

if [ -d "$T" ]; then
    echo "  Template-none already cloned at $T (idempotent re-run)."
elif clone_template "$T"; then
    echo "  Cloned template to $T."
else
    # clone_template declined: either no network + no MVP_TEMPLATE_LOCAL,
    # or MVP_TEMPLATE_LOCAL points at a derived project (issue #15).
    echo "  Smoke instantiate-agent-none assertions will skip (see above for reason)." >&2
    exit 0
fi

# instantiate now resolves the name from origin (F1, chunk 03). Network-clone
# mode leaves origin pointing at the canonical template, which would make the
# derived name 'llm-wiki-memory-template' instead of the basename this test
# asserts. Drop the remote so the name falls back deterministically to the
# clone-dir basename in both network and local modes; this test is about the
# --agent=none set -u regression (issue #9), not naming (see instantiate-naming).
git -C "$T" remote remove origin 2>/dev/null || true

if [ -f "$T/scripts/instantiate.sh" ]; then
    (
        cd "$T"
        # instantiate.sh self-deletes on success, so the outer -f check is
        # the re-run guard; nothing else marks an instantiated tree.
        if [ -f scripts/instantiate.sh ]; then
            rc=0
            bash scripts/instantiate.sh "Agent None Project" \
                --agent=none \
                --description="Regression test for issue #9 (set -u + empty array)." \
                >/tmp/instantiate-none.log 2>&1 || rc=$?
            # rc sidecar outside the tree; assertions.sh asserts rc == 0
            # (a WARN alone let mid-run instantiate deaths pass silently).
            echo "$rc" > "$T.instantiate-rc"
            if [ "$rc" -ne 0 ]; then
                echo "  WARN: instantiate.sh --agent=none failed (rc=$rc); the exit-status assertion will fail." >&2
                sed 's/^/    /' /tmp/instantiate-none.log >&2
            fi
        fi
    )
fi

echo "  Smoke instantiate-agent-none patch applied: template at $T."
