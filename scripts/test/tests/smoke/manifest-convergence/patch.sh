#!/usr/bin/env bash
# Patch: stage TWO sandboxes that ought to converge on the same on-disk
# file set if scripts/lib/template-manifest.sh is the single source of
# truth shared by instantiate, adopt, and update-from-template.
#
# Sandbox A (instantiate):
#   - clone_template into $STAGE/A
#   - run instantiate.sh "Conv A" --agent=none against it
#   - result P1: the file tree of A after bootstrap
#
# Sandbox B (adopt):
#   - virgin git repo at $STAGE/B
#   - run adopt.sh --target=B --apply --agent=claude-code
#   - result P2: the file tree of B after adopt
#
# Why --agent=none for A and --agent=claude-code for B? The convergence
# we are testing is on TEMPLATE_SHARED_INFRA: the set of files that BOTH
# code paths must produce regardless of overlay. instantiate --agent=none
# stops at SHARED; adopt --agent=claude-code produces SHARED + the
# claude overlay. The assertions intersect on SHARED.
#
# Note on update-from-template: a fuller convergence test would also
# stage Sandbox C running adopt then update. It is deferred because
# update-from-template requires a clonable remote (network or a bare
# mirror) and the hermetic harness has no good way to stage one without
# adding fragile machinery. The adopt-vs-instantiate comparison alone is
# enough to prove the manifest is canonical: update reuses the same
# assembler in detection mode and the unit fixture (scripts/test/tests/
# unit/manifest-shape) already verifies the assembler's contract.

set -uo pipefail

HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"
# Force local-clone mode so A is staged from THIS working tree (the same
# source adopt copies from in B). Network mode would clone main, which
# can differ from the branch under test and break the convergence claim
# spuriously. The derived-project guard in clone_template still applies.
export MVP_TEMPLATE_LOCAL="$TEMPLATE_ROOT"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

STAGE="$SANDBOX/manifest-convergence"
A="$STAGE/A"
B="$STAGE/B"
mkdir -p "$STAGE"

# --- Sandbox A: instantiate ---
if [ -d "$A" ]; then
    echo "  manifest-convergence A already staged at $A (idempotent re-run)."
elif clone_template "$A"; then
    echo "  Cloned template into A."
else
    echo "  manifest-convergence assertions will skip: no template clone available." >&2
    exit 0
fi

# clone_template leaves origin unset in local mode. Give it a divergent
# origin so lw_name_from_origin resolves to a recognisable wiki name.
git -C "$A" remote remove origin 2>/dev/null || true
git -C "$A" remote add origin "https://github.com/conv/conv-a.git"

if [ -f "$A/scripts/instantiate.sh" ] && [ ! -f "$A/CLAUDE.md" ]; then
    (
        cd "$A"
        rc=0
        bash scripts/instantiate.sh "Conv A" \
            --agent=none \
            --description="manifest-convergence sandbox A" \
            >/tmp/conv-A.log 2>&1 || rc=$?
        # rc sidecar outside the tree; assertions.sh asserts rc == 0
        # (a WARN alone let mid-run instantiate deaths pass silently).
        echo "$rc" > "$A.instantiate-rc"
        if [ "$rc" -ne 0 ]; then
            echo "  WARN: instantiate failed in A (rc=$rc); the exit-status assertion will fail." >&2
            sed 's/^/    /' /tmp/conv-A.log >&2
        fi
    )
fi

# --- Sandbox B: virgin git + adopt --apply ---
mkdir -p "$B"
if [ ! -d "$B/.git" ]; then
    git init -q "$B"
    git -C "$B" remote add origin "https://github.com/conv/conv-b.git"
    echo "# Conv B" > "$B/README.md"
    git -C "$B" -c user.email=test@x.invalid -c user.name=test add -A
    git -C "$B" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial"
fi

if [ ! -f "$B/llm-wiki.md" ]; then
    ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
    rc=0
    bash "$ADOPT" --target="$B" --apply --agent=claude-code \
        >/tmp/conv-B.log 2>&1 || rc=$?
    # Same rc-sidecar discipline as A: adopt failures were WARN-swallowed too.
    echo "$rc" > "$B.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed in B (rc=$rc); the exit-status assertion will fail." >&2
        sed 's/^/    /' /tmp/conv-B.log >&2
    fi
fi

# --- Stage a third record: what the manifest assembler returns for the
#     adopt call shape. assertions.sh will diff it against the actually
#     installed file set on disk in B.
{
    # shellcheck source=../../../../lib/template-manifest.sh
    source "$TEMPLATE_ROOT/scripts/lib/template-manifest.sh"
    # adopt mode: empty repo_root, AGENT drives overlay inclusion.
    lw_manifest_assemble_active_files "" "claude-code"
    # Sync-tree members (dir mode, same source adopt itself uses, #90).
    lw_manifest_tree_files dir "$TEMPLATE_ROOT"
} > "$STAGE/expected-claude.txt" 2>/dev/null
{
    source "$TEMPLATE_ROOT/scripts/lib/template-manifest.sh"
    lw_manifest_assemble_active_files "" "none"
    lw_manifest_tree_files dir "$TEMPLATE_ROOT"
} > "$STAGE/expected-none.txt" 2>/dev/null

echo "  manifest-convergence patch applied: A=$A B=$B"
