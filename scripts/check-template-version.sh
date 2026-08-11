#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# check-template-version.sh — report drift between this project and the
# llm-wiki template repo. Read-only: applies no changes.
#
# Usage:
#   ./scripts/check-template-version.sh [--template-url=<url>]
#
# Output:
#   - Template HEAD SHA
#   - Last template sync recorded in .llm-wiki-template-log.md (if any)
#   - Per-file status: in sync / out of date / not in template
#   - Suggested next command (update-from-template.sh) if drift exists
#

set -euo pipefail

TEMPLATE_URL="git@github.com:crcresearch/llm-wiki-memory-template.git"

while [[ $# -gt 0 ]]; do
    case $1 in
        --template-url=*) TEMPLATE_URL="${1#*=}"; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Load shared library ---
# The template manifest is sourced AFTER the fetch below, so a host that
# lacks the file can bootstrap it from the template ref (#74).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Shared-lib guard (#92): twin of the one in update-from-template.sh — the
# two cannot share the function because the shared lib is what is missing.
if [[ ! -f "$HERE/lib/common.sh" ]]; then
    {
        echo "error: scripts/lib/common.sh is missing — this checkout predates the shared library."
        echo ""
        echo "A previous update upgraded this script but not its dependencies (the old"
        echo "updater's file list predates scripts/lib/). Recover with adopt:"
        echo ""
        echo "  git clone https://github.com/crcresearch/llm-wiki-memory-template /tmp/llm-wiki-template"
        echo "  bash /tmp/llm-wiki-template/scripts/adopt.sh --target=. --apply --force"
        echo "  ./scripts/check-template-version.sh    # then re-run"
        echo ""
        echo "Background: https://github.com/crcresearch/llm-wiki-memory-template/issues/92"
    } >&2
    exit 1
fi
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

REPO_ROOT=$(lw_repo_root)
# Post-clone authoritative name: the on-disk wiki, not the clone-dir basename
# (F1/F2). Fails loud when the wiki is absent, which is correct for an
# already-instantiated project.
REPO_NAME=$(lw_discover_wiki_name "$REPO_ROOT")
cd "$REPO_ROOT"

# Add the 'template' remote when absent; fail loud if it already points at a
# different repo (F6). Detect the template's default branch (F5).
lw_ensure_remote template "$TEMPLATE_URL"
TEMPLATE_BRANCH=$(lw_default_branch template) || TEMPLATE_BRANCH=main
git fetch --quiet template "$TEMPLATE_BRANCH"
TEMPLATE_REF="template/$TEMPLATE_BRANCH"
TEMPLATE_SHA=$(git rev-parse --short "$TEMPLATE_REF")

# --- Load the template manifest (bootstrap when the host lacks it, #74) ---
# Same self-heal as update-from-template.sh, read-only variant: source a
# TEMP copy from the template ref. The manifest then classifies itself
# into "Missing locally", so the drift report routes the user to
# update-from-template.sh, which installs it.
MANIFEST_PATH="$HERE/lib/template-manifest.sh"
if [[ ! -f "$MANIFEST_PATH" ]]; then
    MANIFEST_PATH=$(mktemp)
    if ! git show "$TEMPLATE_REF:scripts/lib/template-manifest.sh" > "$MANIFEST_PATH" 2>/dev/null; then
        rm -f "$MANIFEST_PATH"
        echo "error: scripts/lib/template-manifest.sh is missing locally AND absent from $TEMPLATE_REF; cannot assemble the file list" >&2
        exit 1
    fi
    echo "note: local scripts/lib/template-manifest.sh missing (host adopted before #74);"
    echo "      using the template's copy for this check. It will report as 'Missing locally'."
fi
# shellcheck source=lib/template-manifest.sh
source "$MANIFEST_PATH"
if [[ "$MANIFEST_PATH" != "$HERE/lib/template-manifest.sh" ]]; then
    rm -f "$MANIFEST_PATH"
fi

# File list assembled via the shared manifest in detection mode (empty
# agent arg, repo_root populated). The two HAS_* flags are reported in
# the summary below; their conditions mirror the manifest accessor's
# overlay-inclusion rules.
HAS_CLAUDE=false
HAS_CURSOR=false
if [[ -d "$REPO_ROOT/.claude" ]] || [[ -d "$REPO_ROOT/wiki/agents/claude-code" ]]; then
    HAS_CLAUDE=true
fi
if [[ -d "$REPO_ROOT/.cursor" ]] || [[ -d "$REPO_ROOT/wiki/agents/cursor" ]]; then
    HAS_CURSOR=true
fi

FILES=()
while IFS= read -r _path; do
    FILES+=("$_path")
done < <(lw_manifest_assemble_active_files "$REPO_ROOT" "")
# Sync-tree members (TEMPLATE_SYNC_TREES) resolved from the template ref (#90).
while IFS= read -r _path; do
    FILES+=("$_path")
done < <(lw_manifest_tree_files ref "$TEMPLATE_REF")

IN_SYNC=()
OUT_OF_DATE=()
NOT_IN_TEMPLATE=()
LOCAL_MISSING=()

for f in "${FILES[@]}"; do
    if ! git cat-file -e "$TEMPLATE_REF:$f" 2>/dev/null; then
        NOT_IN_TEMPLATE+=("$f"); continue
    fi
    # Materialize via temp file so the trailing newline survives the hash.
    TEMPLATE_TMP=$(mktemp)
    git show "$TEMPLATE_REF:$f" > "$TEMPLATE_TMP"
    if lw_manifest_needs_substitution "$f"; then
        sed -i.bak "s|{{REPO_NAME}}|$REPO_NAME|g" "$TEMPLATE_TMP"
        rm -f "${TEMPLATE_TMP}.bak"
    fi
    TEMPLATE_HASH=$(lw_sha256 "$TEMPLATE_TMP")
    rm -f "$TEMPLATE_TMP"

    if [[ ! -f "$f" ]]; then
        LOCAL_MISSING+=("$f"); continue
    fi
    LOCAL_HASH=$(lw_sha256 "$f")
    if [[ "$LOCAL_HASH" == "$TEMPLATE_HASH" ]]; then
        IN_SYNC+=("$f")
    else
        OUT_OF_DATE+=("$f")
    fi
done

# --- Report ---
echo ""
echo "================ check-template-version ================"
echo "Repo:     $REPO_ROOT ($REPO_NAME)"
echo "Template: $TEMPLATE_URL @ $TEMPLATE_SHA"
echo "Overlays present:  claude-code=$HAS_CLAUDE  cursor=$HAS_CURSOR"

# Last sync (from log)
LOG_FILE="$REPO_ROOT/.llm-wiki-template-log.md"
if [[ -f "$LOG_FILE" ]]; then
    LAST=$(grep -E '^## \[' "$LOG_FILE" | tail -1)
    echo "Last sync:   $LAST"
else
    echo "Last sync:   <no .llm-wiki-template-log.md found>"
fi
echo "--------------------------------------------------------"
echo "In sync (${#IN_SYNC[@]}):"
if [[ ${#IN_SYNC[@]} -gt 0 ]]; then
    for f in "${IN_SYNC[@]}"; do echo "  = $f"; done
fi
echo ""
echo "Out of date (${#OUT_OF_DATE[@]}):"
if [[ ${#OUT_OF_DATE[@]} -gt 0 ]]; then
    for f in "${OUT_OF_DATE[@]}"; do echo "  ! $f"; done
fi
if [[ ${#LOCAL_MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "Missing locally (${#LOCAL_MISSING[@]}):"
    for f in "${LOCAL_MISSING[@]}"; do echo "  ? $f"; done
fi
if [[ ${#NOT_IN_TEMPLATE[@]} -gt 0 ]]; then
    echo ""
    echo "Not in template (${#NOT_IN_TEMPLATE[@]}):"
    for f in "${NOT_IN_TEMPLATE[@]}"; do echo "  - $f"; done
fi

# .gitignore advisory: host-owned (TEMPLATE_HOST_OWNED), so it does not
# appear in the FILES list and never reports as out-of-date. Surface the
# divergence here so reviewers know template improvements exist; the host
# decides whether to back-port. Mirrors update-from-template's advisory.
if git cat-file -e "$TEMPLATE_REF:.gitignore" 2>/dev/null && [[ -f "$REPO_ROOT/.gitignore" ]]; then
    TEMPLATE_GI=$(mktemp)
    git show "$TEMPLATE_REF:.gitignore" > "$TEMPLATE_GI"
    if ! cmp -s "$REPO_ROOT/.gitignore" "$TEMPLATE_GI"; then
        echo ""
        echo "Advisory: .gitignore is host-owned. Template's .gitignore differs."
        echo "          Inspect with: git diff $TEMPLATE_REF -- .gitignore"
    fi
    rm -f "$TEMPLATE_GI"
fi
echo "========================================================"
echo ""

if [[ ${#OUT_OF_DATE[@]} -gt 0 ]] || [[ ${#LOCAL_MISSING[@]} -gt 0 ]]; then
    echo "Drift detected. To preview a sync:"
    echo "  ./scripts/update-from-template.sh --dry-run"
    echo "To apply:"
    echo "  ./scripts/update-from-template.sh"
    exit 1
fi

echo "All tracked files in sync with template @ $TEMPLATE_SHA."
