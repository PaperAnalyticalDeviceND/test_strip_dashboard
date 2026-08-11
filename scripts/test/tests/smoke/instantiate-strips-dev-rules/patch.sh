#!/usr/bin/env bash
# Smoke test: instantiate.sh strips the template-development-only .claude/rules/.
#
# .claude/rules/ ships guidance for contributors working ON the template
# (e.g. observe-the-failure.md), not behaviour a derived project needs.
# instantiate.sh removes that directory during real instantiation so it does
# not propagate. This runs a real --agent=claude-code instantiation (which
# otherwise KEEPS .claude/ for commands/skills), so the strip is observable
# in isolation: .claude/ survives, .claude/rules/ specifically does not.
#
# Inputs:  SANDBOX env var. lib/template.sh's clone_template.
# Effects: $SANDBOX/template-dev-rules/ contains a derivative.
#          $SANDBOX/dev-rules-was-present is created iff the cloned template
#          shipped .claude/rules/ BEFORE instantiation, so the "absent after"
#          assertion is not vacuous (it must have been present to be stripped).
#
# Idempotent.

set -euo pipefail

HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

T="$SANDBOX/template-dev-rules"

if [ -d "$T" ]; then
    echo "  Template already cloned at $T (idempotent re-run)."
elif clone_template "$T"; then
    echo "  Cloned template to $T."
else
    # clone_template declined: no network + no MVP_TEMPLATE_LOCAL, or
    # MVP_TEMPLATE_LOCAL points at a derived project (issue #15).
    echo "  Smoke instantiate-strips-dev-rules assertions will skip (see above)." >&2
    exit 0
fi

# Record the pre-instantiation state. The "stripped after" assertion is only
# meaningful if the directory was actually shipped by the template; a derived
# project that never had .claude/rules/ would pass it trivially.
if [ -f "$T/.claude/rules/observe-the-failure.md" ]; then
    : > "$SANDBOX/dev-rules-was-present"
fi
if [ -f "$T/.claude/rules/local-testing.md" ]; then
    : > "$SANDBOX/local-testing-rule-was-present"
fi

# Drop a synthetic consumer-facing rule alongside the dev-only one. The strip
# must remove only the named dev-only rule(s); this sibling must survive. It
# also guards against regressing to a whole-directory `rm -rf`, which would
# delete it too.
if [ -d "$T/.claude/rules" ]; then
    printf '%s\n' "# A project's own rule — must survive instantiation." \
        > "$T/.claude/rules/keep-me.md"
fi

if [ -f "$T/scripts/instantiate.sh" ] && [ ! -f "$T/CLAUDE.md" ]; then
    (
        cd "$T"
        rc=0
        bash scripts/instantiate.sh "Dev Rules Project" \
            --agent=claude-code \
            --description="Smoke test: dev-only .claude/rules/ is stripped." \
            >/tmp/instantiate-dev-rules.log 2>&1 || rc=$?
        # rc sidecar outside the tree; assertions.sh asserts rc == 0
        # (a WARN alone let mid-run instantiate deaths pass silently).
        echo "$rc" > "$T.instantiate-rc"
        if [ "$rc" -ne 0 ]; then
            echo "  WARN: instantiate.sh failed (rc=$rc); the exit-status assertion will fail." >&2
            sed 's/^/    /' /tmp/instantiate-dev-rules.log >&2
        fi
    )
fi

echo "  Smoke instantiate-strips-dev-rules patch applied: template at $T."
