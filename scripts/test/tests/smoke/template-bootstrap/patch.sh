#!/usr/bin/env bash
# Smoke test: template bootstrap.
# Clones the real llm-wiki-memory-template (or uses local copy via
# MVP_TEMPLATE_LOCAL), runs instantiate.sh to bootstrap a fresh derivative,
# then verifies the template's own scripts produced expected outputs.
#
# This is the answer to template issue #5's "create-mode run of init-wiki.sh
# in a throwaway repo, asserting the wiki files and the expected SCHEMA
# sections are generated" request, scoped to what can run without an LLM
# in the loop.
#
# Inputs:  SANDBOX env var. lib/template.sh's clone_template function.
# Effects: $SANDBOX/template/ contains a freshly-bootstrapped derivative
#          if the clone succeeded. assertions.sh inspects it.
#
# Idempotent.

set -euo pipefail

# Source the harness lib so clone_template is available in this subshell.
# (run.sh sources lib/*.sh in its own scope; patch.sh runs in a subshell
# and needs to load them again.)
HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

T="$SANDBOX/template"

# Clone the template
if [ -d "$T" ]; then
    echo "  Template already cloned at $T (idempotent re-run)."
elif clone_template "$T"; then
    echo "  Cloned template to $T."
else
    # clone_template declined: either no network + no MVP_TEMPLATE_LOCAL,
    # or MVP_TEMPLATE_LOCAL points at a derived project (issue #15).
    # clone_template prints the specific reason to stderr; we just skip.
    echo "  Smoke template-bootstrap assertions will skip (see above for reason)." >&2
    exit 0
fi

# Run the template's own bootstrap (instantiate.sh).
# This is the entry point the template documents for first-use.
if [ -f "$T/scripts/instantiate.sh" ]; then
    (
        cd "$T"
        # instantiate.sh self-deletes on success, so the -f check is the
        # re-run guard; nothing else marks an instantiated tree.
        if [ -f scripts/instantiate.sh ]; then
            # Use --agent=claude-code (the documented default) to exercise
            # the claude-code overlay. The --agent=none path is covered
            # separately by the instantiate-agent-none smoke test (issue #9
            # regression).
            rc=0
            bash scripts/instantiate.sh "Smoke Test Project" \
                --agent=claude-code \
                --description="Bootstrapping the template inside the harness sandbox." \
                >/tmp/instantiate.log 2>&1 || rc=$?
            # Sidecar, not in-tree: a file inside $T would pollute the
            # derivative the assertions inspect. assertions.sh asserts
            # rc == 0 — the previous WARN-only handling let a mid-run
            # instantiate death pass the whole suite with 0 fail (every
            # downstream assertion is presence-conditional).
            echo "$rc" > "$T.instantiate-rc"
            if [ "$rc" -ne 0 ]; then
                echo "  WARN: instantiate.sh failed (rc=$rc); the exit-status assertion will fail." >&2
                sed 's/^/    /' /tmp/instantiate.log >&2
            fi
        fi
    )
fi

echo "  Smoke template-bootstrap patch applied: template at $T (instantiate run if needed)."
