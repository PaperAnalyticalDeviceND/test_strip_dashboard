#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# update-from-template.sh — pull updates from the llm-wiki template repo into
# an existing project, without touching project-specific content.
#
# Usage:
#   ./scripts/update-from-template.sh [--dry-run] [--template-url=<url>]
#
# Flags:
#   --dry-run        Print what would change without writing anything.
#   --template-url   Override the template remote URL. Defaults to the
#                    crcresearch/llm-wiki-memory-template repo. Pass this only if
#                    your org maintains a fork.
#
# What gets updated:
#   The active file set is assembled by lw_manifest_assemble_active_files
#   from scripts/lib/template-manifest.sh, which is the single source of
#   truth: TEMPLATE_SHARED_INFRA always syncs; TEMPLATE_OVERLAY_CLAUDE and
#   TEMPLATE_OVERLAY_CURSOR activate based on .claude/ and .cursor/ presence
#   on disk. {{REPO_NAME}} substitution targets are listed in
#   TEMPLATE_SUBSTITUTE_FILES. To add or remove a synced file, edit the
#   manifest and nothing else.
#
# What does NOT get touched (project-specific):
#   .claude/settings.json                         (TEMPLATE_HOST_OWNED: the
#       template defines the operation type but the host owns the content)
#   CLAUDE.md, .gitignore                         (plain host content; the
#       template never creates or edits them)
#   README.md                                     (project's own)
#   .claude/settings.local.json                   (per-user, gitignored)
#   .claude/hooks/                                (per-machine, opt-in)
#   wiki/<repo>.wiki/                             (separate git sub-repo)
#   Any file under your project's source tree
#
# .gitignore note: earlier versions of this script synced .gitignore as part
# of the former always-synced list. It is now host-owned. The advisory in the post-sync
# report flags a divergence if the host's .gitignore differs from the
# template's; back-port manually if you want the new ignore rule.
#
# After each successful run, an entry is appended to .llm-wiki-template-log.md
# at the repo root, recording the template commit SHA and the files changed.
# Push: this script does NOT push. It stages changes locally (unless --dry-run).
#

set -euo pipefail

DRY_RUN=false
TEMPLATE_URL="git@github.com:crcresearch/llm-wiki-memory-template.git"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)            DRY_RUN=true; shift ;;
        --template-url=*)     TEMPLATE_URL="${1#*=}"; shift ;;
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
# Shared-lib guard (#92): on inline-era hosts, run 1 of the standard flow
# delivers this newer updater off the old inline list — which predates
# scripts/lib/ — and a raw `source` death here bricked the flow with no
# guidance. Healing is deliberately NOT automatic (the fetch helpers live
# in the very lib that is missing; the affected population is enumerable);
# the recovery is adopt. Twin guard in check-template-version.sh — the two
# cannot share the function precisely because the shared lib is the thing
# that is absent.
if [[ ! -f "$HERE/lib/common.sh" ]]; then
    {
        echo "error: scripts/lib/common.sh is missing — this checkout predates the shared library."
        echo ""
        echo "A previous update upgraded this script but not its dependencies (the old"
        echo "updater's file list predates scripts/lib/). Recover with adopt:"
        echo ""
        echo "  git clone https://github.com/crcresearch/llm-wiki-memory-template /tmp/llm-wiki-template"
        echo "  bash /tmp/llm-wiki-template/scripts/adopt.sh --target=. --apply --force"
        echo "  ./scripts/update-from-template.sh    # then re-run"
        echo ""
        echo "Background: https://github.com/crcresearch/llm-wiki-memory-template/issues/92"
    } >&2
    exit 1
fi
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

REPO_ROOT=$(lw_repo_root)
# Post-clone: the authoritative name is the on-disk wiki, not the clone-dir
# basename (F1/F2). A fork or renamed clone makes the basename wrong; the
# committed wiki/<name>.wiki is the only correct source. Fails loud if the wiki
# is absent, which is correct here: this script is for already-instantiated
# projects.
REPO_NAME=$(lw_discover_wiki_name "$REPO_ROOT")
cd "$REPO_ROOT"

# --- Ensure 'template' remote exists and points at the expected repo ---
# lw_ensure_remote adds it when absent and, when present, fails loud if it
# points at a different repo rather than silently fetching from the wrong
# place (F6). Pass --template-url to point at an org fork.
lw_ensure_remote template "$TEMPLATE_URL"

# Detect the template's default branch instead of assuming 'main' (F5).
TEMPLATE_BRANCH=$(lw_default_branch template) || TEMPLATE_BRANCH=main
echo "Fetching template@${TEMPLATE_BRANCH} ..."
git fetch --quiet template "$TEMPLATE_BRANCH"

TEMPLATE_REF="template/$TEMPLATE_BRANCH"
TEMPLATE_SHA=$(git rev-parse --short "$TEMPLATE_REF")
echo "Template HEAD: $TEMPLATE_SHA"

# --- Load the template manifest (self-heal when the host's copy can't) ---
# Two vintages need healing. Hosts adopted before the manifest shipped
# itself (#74) have an updater whose file list lives in a file they never
# received; sourcing it directly would die before the fetch that could
# deliver the fix. Hosts instantiated between #60 and #76 have a manifest
# that is PRESENT but does not list itself, so a sync assembled from it can
# never deliver its own replacement. In both cases, materialize the
# manifest from the just-fetched template ref into a TEMP file and source
# that — the sync loop below then installs/updates the on-disk copy like
# any other manifest-listed file (or reports it, on --dry-run).
MANIFEST_PATH="$HERE/lib/template-manifest.sh"
_manifest_heal_reason=""
if [[ ! -f "$MANIFEST_PATH" ]]; then
    _manifest_heal_reason="missing (host adopted before #74)"
elif ! grep -qF '"scripts/lib/template-manifest.sh"' "$MANIFEST_PATH"; then
    # Present but stale: a pre-#76 manifest does not list itself, so a sync
    # assembled from it can never deliver its own replacement — the host
    # stays on the old file list forever (hosts instantiated between #60
    # and #76; first field case: naval-sensor-fusion, 2026-06-30 vintage).
    # Every post-#76 manifest carries its own path as an array entry, so
    # the quoted-string probe is an unambiguous vintage signature.
    _manifest_heal_reason="present but stale (predates #76: does not list itself)"
fi
if [[ -n "$_manifest_heal_reason" ]]; then
    MANIFEST_PATH=$(mktemp)
    if ! git show "$TEMPLATE_REF:scripts/lib/template-manifest.sh" > "$MANIFEST_PATH" 2>/dev/null; then
        rm -f "$MANIFEST_PATH"
        echo "error: scripts/lib/template-manifest.sh is unusable locally AND absent from $TEMPLATE_REF; cannot assemble the sync file list" >&2
        exit 1
    fi
    if [[ "$_manifest_heal_reason" == missing* ]]; then
        # Wording kept verbatim from the #74 fix (the adopted-host-sync
        # fixture pins it as the legacy host's observable signal).
        echo "note: local scripts/lib/template-manifest.sh missing (host adopted before #74);"
        echo "      bootstrapped this run's copy from $TEMPLATE_REF. The sync below installs it."
    else
        echo "note: local scripts/lib/template-manifest.sh $_manifest_heal_reason;"
        echo "      using $TEMPLATE_REF's copy for this run. The sync below updates it on disk."
    fi
fi
# shellcheck source=lib/template-manifest.sh
source "$MANIFEST_PATH"
if [[ "$MANIFEST_PATH" != "$HERE/lib/template-manifest.sh" ]]; then
    rm -f "$MANIFEST_PATH"
fi

# --- Build the file list ---
# All path enumeration lives in scripts/lib/template-manifest.sh. The
# accessor returns SHARED_INFRA always plus overlay arrays based on the
# host's .claude/ and .cursor/ presence (detection mode: empty agent arg,
# repo_root populated). Bash 3.2 portable: while read instead of mapfile.
FILES=()
while IFS= read -r _path; do
    FILES+=("$_path")
done < <(lw_manifest_assemble_active_files "$REPO_ROOT" "")
# Sync-tree members (TEMPLATE_SYNC_TREES, e.g. the test harness) resolved
# from the template ref — membership is never a static list (#90).
while IFS= read -r _path; do
    FILES+=("$_path")
done < <(lw_manifest_tree_files ref "$TEMPLATE_REF")

# --- Diff and apply ---
CHANGED=()
SKIPPED=()
MISSING_IN_TEMPLATE=()

for f in "${FILES[@]}"; do
    # Does the file exist in the template's default branch?
    if ! git cat-file -e "$TEMPLATE_REF:$f" 2>/dev/null; then
        MISSING_IN_TEMPLATE+=("$f")
        continue
    fi

    # Materialize the template version to a temp file so the byte-exact
    # comparison preserves trailing newlines. Using a bash variable + sha256sum
    # via pipe would strip the trailing \n and produce false "changed" reports.
    TEMPLATE_TMP=$(mktemp)
    git show "$TEMPLATE_REF:$f" > "$TEMPLATE_TMP"
    if lw_manifest_needs_substitution "$f"; then
        # GNU sed: -i without backup. macOS sed needs -i ''. Use a portable
        # form via the .bak suffix and clean up after.
        sed -i.bak "s|{{REPO_NAME}}|$REPO_NAME|g" "$TEMPLATE_TMP"
        rm -f "${TEMPLATE_TMP}.bak"
    fi

    TEMPLATE_HASH=$(lw_sha256 "$TEMPLATE_TMP")
    if [[ -f "$f" ]]; then
        LOCAL_HASH=$(lw_sha256 "$f")
    else
        LOCAL_HASH="<missing>"
    fi

    if [[ "$LOCAL_HASH" == "$TEMPLATE_HASH" ]]; then
        SKIPPED+=("$f")
        rm -f "$TEMPLATE_TMP"
        continue
    fi

    CHANGED+=("$f")
    if ! $DRY_RUN; then
        mkdir -p "$(dirname "$f")"
        mv "$TEMPLATE_TMP" "$f"
        # Preserve executable bit for shell scripts that should be executable.
        case "$f" in
            *.sh) chmod +x "$f" ;;
        esac
    else
        rm -f "$TEMPLATE_TMP"
    fi
done

# --- Report ---
echo ""
echo "================ update-from-template ================"
echo "Repo:     $REPO_ROOT"
echo "Template: $TEMPLATE_URL @ $TEMPLATE_SHA"
echo "Mode:     $($DRY_RUN && echo 'DRY RUN' || echo 'APPLIED')"
echo "------------------------------------------------------"
echo "Changed (${#CHANGED[@]}):"
if [[ ${#CHANGED[@]} -gt 0 ]]; then
    for f in "${CHANGED[@]}"; do echo "  + $f"; done
fi
echo ""
echo "Skipped, identical to template (${#SKIPPED[@]}):"
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    for f in "${SKIPPED[@]}"; do echo "  = $f"; done
fi
if [[ ${#MISSING_IN_TEMPLATE[@]} -gt 0 ]]; then
    echo ""
    echo "Not present in ${TEMPLATE_REF} (${#MISSING_IN_TEMPLATE[@]}):"
    for f in "${MISSING_IN_TEMPLATE[@]}"; do echo "  ? $f"; done
fi

# .gitignore advisory: the file is host-owned (TEMPLATE_HOST_OWNED). Earlier
# versions of this script synced it as part of the former always-synced list;
# the host now owns the content. If the template's .gitignore has rules the
# host lacks, back-port them manually. Probe TEMPLATE_REF directly because
# .gitignore is absent from the assembled FILES list.
if git cat-file -e "$TEMPLATE_REF:.gitignore" 2>/dev/null && [[ -f "$REPO_ROOT/.gitignore" ]]; then
    TEMPLATE_GI=$(mktemp)
    git show "$TEMPLATE_REF:.gitignore" > "$TEMPLATE_GI"
    if ! cmp -s "$REPO_ROOT/.gitignore" "$TEMPLATE_GI"; then
        echo ""
        echo "Advisory: .gitignore is host-owned (was synced in earlier versions)."
        echo "          The template's .gitignore differs from yours. This script"
        echo "          will not overwrite it. Review with:"
        echo "            git diff $TEMPLATE_REF -- .gitignore"
        echo "          (The wiki sub-repo ignore rule ships as wiki/.gitignore,"
        echo "          a synced template file, so it needs no back-porting.)"
    fi
    rm -f "$TEMPLATE_GI"
fi
echo "======================================================"

if $DRY_RUN; then
    echo ""
    echo "Dry run only. Re-run without --dry-run to apply."
    exit 0
fi

if [[ ${#CHANGED[@]} -eq 0 ]]; then
    echo ""
    echo "Nothing to apply. Repo is in sync with ${TEMPLATE_REF} @ $TEMPLATE_SHA."
    exit 0
fi

# --- Append log entry ---
LOG_FILE="$REPO_ROOT/.llm-wiki-template-log.md"
TODAY=$(date +%Y-%m-%d)
# shellcheck disable=SC2094  # the -f tests only probe existence; the block appends
{
    [[ -f "$LOG_FILE" ]] || echo "# llm-wiki template sync log"
    [[ -f "$LOG_FILE" ]] || echo ""
    echo "## [$TODAY] pulled template @${TEMPLATE_SHA} - ${#CHANGED[@]} file(s) updated"
    for f in "${CHANGED[@]}"; do echo "- $f"; done
    echo ""
} >> "$LOG_FILE"

echo ""
echo "Logged in .llm-wiki-template-log.md."
echo ""
echo "Next steps:"
echo "  Review the changes:    git diff"
echo "  Stage and commit:      git add -A && git commit -m \"chore: pull llm-wiki template @${TEMPLATE_SHA}\""
echo "  (Do NOT push unless the team has reviewed.)"
