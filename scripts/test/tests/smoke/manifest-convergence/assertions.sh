#!/usr/bin/env bash
# Assertions: prove the manifest is the single source of truth shared by
# instantiate (path A) and adopt --apply (path B). For every file the
# manifest classifies as TEMPLATE_SHARED_INFRA, both code paths must
# install a byte-equal copy.
#
# Asymmetric files (those expected to differ by design) are listed in
# the allowlist with a one-line rationale. Each allowlist entry weakens
# the test; keep the list tight.

STAGE="$SANDBOX/manifest-convergence"
A="$STAGE/A"
B="$STAGE/B"
REPO_ROOT_LIB="$(cd "$HERE/../.." && pwd)"

# Patch declines (exit 0, nothing staged) when no usable template source
# exists: offline, or TEMPLATE_ROOT is itself a derived project — this
# harness ships to derived projects via "Use this template", where
# clone_template's issue-#15 guard refuses the copy. Skip like the five
# sibling smoke tests instead of failing four staging assertions that can
# never hold in a derived checkout (observed: 4 spurious fails in every
# derived project's CI).
if [ ! -d "$A" ]; then
    skip "manifest-convergence assertions" "no template clone available (offline, or run inside a derived project)"
    return 0 2>/dev/null || true
fi

# --- Sanity: both sandboxes exist ------------------------------------------
assert "manifest-convergence A staged"     "[ -d '$A' ]"
assert "manifest-convergence B staged"     "[ -d '$B' ]"
assert "expected-claude.txt produced"      "[ -s '$STAGE/expected-claude.txt' ]"
assert "expected-none.txt produced"        "[ -s '$STAGE/expected-none.txt' ]"

# Bail cleanly if A failed to bootstrap (e.g. clone_template skipped
# because no template is available offline). The "staged" assertions
# above surface that and the rest become no-ops via the [ -d ] guard.
if [ ! -f "$A/llm-wiki.md" ]; then
    skip "manifest-convergence body assertions" "sandbox A not bootstrapped (clone_template likely skipped)"
    return 0
fi

# Exit statuses first: the convergence comparison below only inspects
# files that exist, so a mid-run death in either code path could still
# converge trivially (both rc's were WARN-swallowed before).
assert "instantiate (A) exited 0" \
    "[ \"\$(cat '$A.instantiate-rc' 2>/dev/null)\" = '0' ]"
assert "adopt --apply (B) exited 0" \
    "[ \"\$(cat '$B.adopt-rc' 2>/dev/null)\" = '0' ]"

# --- Manifest IS what adopt installed --------------------------------------
# Iterate the expected list (adopt mode, AGENT=claude-code). Every entry
# must exist on disk in B. Any failure here means adopt did NOT install
# a manifest-listed file, which is exactly the kind of drift the
# consolidation is meant to detect.
while IFS= read -r _path; do
    [[ -n "$_path" ]] || continue
    assert "B has manifest-listed path: $_path" \
        "[ -e '$B/$_path' ]"
done < "$STAGE/expected-claude.txt"

# Bonus check: nothing UNEXPECTED installed (every manifest-managed file
# came from the manifest, no orphans). Compare the list of regular files
# under B/<predictable-dirs>/ against expected-claude.txt; flag extras
# that are not host-authored.
# Keep this scoped to directories the manifest owns end-to-end; B's
# README and .git are host-authored and out of scope.

# --- Convergence: A and B agree on TEMPLATE_SHARED_INFRA -------------------
# For each path that appears in BOTH instantiate (A) and adopt (B) output,
# assert byte-equality. Allowlist documents known-asymmetric files.
ALLOWLIST=(
    # CLAUDE.md is host-owned and no longer produced by either path;
    # allowlisted defensively in case a host authors one.
    "CLAUDE.md"
    # README.md is host-authored (B) or .template-rendered (A); never
    # synced by either tool.
    "README.md"
    # .claude/settings.json: instantiate copies the .template; adopt may
    # leave the host's untouched (HOST_OWNED merge). The shape converges
    # over time but the byte content does not, and HOST_OWNED is exactly
    # the contract that says don't enforce equality here.
    ".claude/settings.json"
    # .gitignore: host-owned and never touched by adopt. A picks up the
    # template's; B keeps the host's own. Different by design; the wiki
    # ignore rule converges via wiki/.gitignore (SHARED_INFRA).
    ".gitignore"
    # wiki/<name>.wiki/: separate git remote, not synced.
    # The convergence loop below filters wiki/*.wiki/ prefixes wholesale.
)

is_allowlisted() {
    local p="$1" w
    for w in "${ALLOWLIST[@]}"; do
        [[ "$p" == "$w" ]] && return 0
    done
    # Wiki sub-repo path prefix (project-specific name; cannot enumerate).
    case "$p" in
        wiki/*.wiki/*) return 0 ;;
    esac
    return 1
}

# Convergence loop: assemble TEMPLATE_SHARED_INFRA via the manifest and
# diff each path between A and B. A used --agent=none (no overlay), so we
# only compare SHARED_INFRA; the overlay-specific files are separately
# covered by manifest-shape (existence) and the adopt-virgin-with-claude
# integration (functional installation).
SHARED_INFRA="$(
    set -e
    # shellcheck source=/dev/null
    source "$REPO_ROOT_LIB/scripts/lib/template-manifest.sh"
    printf '%s\n' "${TEMPLATE_SHARED_INFRA[@]}"
)"

CONVERGED=0
DIVERGED=0
while IFS= read -r _path; do
    [[ -n "$_path" ]] || continue
    if is_allowlisted "$_path"; then
        continue
    fi
    if [ ! -f "$A/$_path" ]; then
        # A didn't install it (e.g. wiki/<name>.wiki/ files), skip
        continue
    fi
    if [ ! -f "$B/$_path" ]; then
        # B failed to install it -- already caught by the existence loop
        # above; do not double-report.
        continue
    fi
    if cmp -s "$A/$_path" "$B/$_path"; then
        CONVERGED=$((CONVERGED + 1))
    else
        DIVERGED=$((DIVERGED + 1))
        assert "A and B byte-equal on SHARED_INFRA path: $_path" \
            "cmp -s '$A/$_path' '$B/$_path'"
    fi
done <<< "$SHARED_INFRA"

# Report the converged count as a positive assertion so the test log
# shows a green count, not just absence of red. Catches the inverse
# failure mode: ALL files were allowlisted and the test silently
# verified nothing.
assert "at least 20 SHARED_INFRA paths byte-equal between A and B" \
    "[ $CONVERGED -ge 20 ]"

# --- Adopt did not produce file count outside the manifest -----------------
# Walk B's tracked manifest-managed directories and confirm every file
# we find IS in the expected list. Catches the inverse drift: adopt
# installs a file the manifest does not enumerate.
EXTRAS=()
while IFS= read -r _disk; do
    [[ -n "$_disk" ]] || continue
    # Skip wiki sub-repo (separate git remote, not manifest-managed)
    case "$_disk" in
        wiki/*.wiki/*) continue ;;
        .git/*) continue ;;
        # Host-authored files that pre-existed: README.md, .git/
        README.md) continue ;;
        # Host-owned files (merge grant or plain host content): the
        # manifest lists .claude/settings.json in TEMPLATE_HOST_OWNED,
        # not SHARED_INFRA; CLAUDE.md and .gitignore are plain host
        # content that may pre-exist. Treated as host content by sync
        # tools either way.
        CLAUDE.md|.gitignore|.claude/settings.json) continue ;;
        # Adopt's own log artifact: not a manifest entry.
        .llm-wiki-adopt-log.md|.llm-wiki-template-log.md) continue ;;
        # Hook scripts in .claude/hooks/ are runtime-installed by the
        # overlay's setup.sh --hook subcommand; not in TEMPLATE_SHARED.
        .claude/hooks/*) continue ;;
        # Per-user / per-machine files; gitignored by adopt's payload.
        .claude/settings.local.json) continue ;;
        # init-wiki creates an index at wiki/WIKI-INDEX.md as a runtime
        # registry of project wikis on the host; not a manifest-managed
        # path.
        wiki/WIKI-INDEX.md) continue ;;
    esac
    if ! grep -qxF -- "$_disk" "$STAGE/expected-claude.txt"; then
        EXTRAS+=("$_disk")
    fi
done < <(cd "$B" && find . -type f -not -path './.git/*' -not -path './wiki/*.wiki/*' | sed 's#^\./##' | sort)

if [ ${#EXTRAS[@]} -gt 0 ]; then
    echo "    EXTRAS not in expected-claude.txt:" >&2
    printf '      %s\n' "${EXTRAS[@]}" >&2
fi
assert "B contains no orphan files outside the manifest contract" \
    "[ ${#EXTRAS[@]} -eq 0 ]"
