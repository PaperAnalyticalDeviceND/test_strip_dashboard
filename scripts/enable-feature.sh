#!/usr/bin/env bash
#
# enable-feature.sh — Retroactive entry point for enabling a feature in a
# project that was instantiated from the llm-wiki-memory template.
#
# Use this when the feature was not selected at instantiation time (via
# instantiate.sh --features=) and you want to add it later.
#
# Usage:
#   ./scripts/enable-feature.sh <feature-name>
#   ./scripts/enable-feature.sh --list
#   ./scripts/enable-feature.sh -h | --help
#
# Effects:
#   - Reads features/<name>/feature.json
#   - Copies feature files into the project
#   - Installs the feature's rule file at .claude/rules/feature-<name>.md
#   - Copies the feature's CI workflow into .github/workflows/
#   - Records the feature name in .features-enabled
#   - Prints system dependency install instructions
#
# Idempotent: re-running with the same feature is a no-op success.
#
# Run from the project root (the directory containing llm-wiki.md).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/.." && pwd)"

# --- Parse args ---
LIST=0
NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            LIST=1; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        --*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            if [[ -z "$NAME" ]]; then
                NAME="$1"
            else
                echo "Error: only one feature name accepted." >&2
                exit 1
            fi
            shift ;;
    esac
done

# --- Sanity check: this looks like a template-derived project ---
cd "$PROJECT_ROOT"
# llm-wiki.md is the template's always-present marker (SHARED_INFRA,
# delivered by both instantiate and adopt). CLAUDE.md is NOT used here:
# it is host-owned and a derived project may legitimately not have one.
if [[ ! -f "llm-wiki.md" ]]; then
    echo "Error: no llm-wiki.md at $PROJECT_ROOT." >&2
    echo "       enable-feature.sh expects to run from a project that was" >&2
    echo "       instantiated from crcresearch/llm-wiki-memory-template." >&2
    exit 1
fi

# --- Load install_feature ---
# shellcheck source=lib/install-feature.sh
source "$HERE/lib/install-feature.sh"

# --- --list mode: enumerate available features and exit ---
if [[ "$LIST" -eq 1 ]]; then
    FEATURES_DIR_RESOLVED="$(_feature_features_dir)"
    if [[ ! -d "$FEATURES_DIR_RESOLVED" ]]; then
        echo "No features/ directory found at $FEATURES_DIR_RESOLVED."
        exit 0
    fi
    echo "Available features in $FEATURES_DIR_RESOLVED/:"
    found=0
    for d in "$FEATURES_DIR_RESOLVED"/*/; do
        [[ -d "$d" ]] || continue
        [[ -f "$d/feature.json" ]] || continue
        n=$(basename "$d")
        d_json="$d/feature.json"
        desc=""
        if command -v jq >/dev/null 2>&1; then
            desc=$(jq -r '.description // empty' "$d_json")
        fi
        if [[ -f ".features-enabled" ]] && grep -qFx "$n" .features-enabled 2>/dev/null; then
            tag="[enabled]"
        else
            tag="[available]"
        fi
        printf "  %-20s %s\n" "$n $tag" "$desc"
        found=1
    done
    if [[ "$found" -eq 0 ]]; then
        echo "  (none)"
    fi
    exit 0
fi

# --- Require a feature name ---
if [[ -z "$NAME" ]]; then
    echo "Error: feature name is required." >&2
    echo "Usage: $0 <feature-name>" >&2
    echo "       $0 --list" >&2
    exit 1
fi

install_feature "$NAME"
