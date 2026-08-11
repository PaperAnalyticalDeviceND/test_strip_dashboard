#!/usr/bin/env bash
#
# disable-feature.sh — Symmetric removal of a feature previously enabled
# in a project derived from the llm-wiki-memory template.
#
# Usage:
#   ./scripts/disable-feature.sh <feature-name>
#   ./scripts/disable-feature.sh -h | --help
#
# Effects (mirror of enable-feature.sh / install_feature):
#   - Removes the files copied by install (files.destination)
#   - Removes the tests copied by install (tests.destination)
#   - Removes the CI workflow file
#   - Removes the feature's rule file at .claude/rules/feature-<name>.md
#   - Removes the feature name from .features-enabled
#
# Idempotent: removing a feature that is not enabled is a no-op success.
#
# Run from the project root (the directory containing llm-wiki.md).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/.." && pwd)"

# --- Parse args ---
NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
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

if [[ -z "$NAME" ]]; then
    echo "Error: feature name is required." >&2
    echo "Usage: $0 <feature-name>" >&2
    exit 1
fi

# --- Sanity check: this looks like a template-derived project ---
cd "$PROJECT_ROOT"
# llm-wiki.md is the template's always-present marker (SHARED_INFRA,
# delivered by both instantiate and adopt). CLAUDE.md is NOT used here:
# it is host-owned and a derived project may legitimately not have one.
if [[ ! -f "llm-wiki.md" ]]; then
    echo "Error: no llm-wiki.md at $PROJECT_ROOT." >&2
    echo "       disable-feature.sh expects to run from a project that was" >&2
    echo "       instantiated from crcresearch/llm-wiki-memory-template." >&2
    exit 1
fi

# --- Load uninstall_feature ---
# shellcheck source=lib/install-feature.sh
source "$HERE/lib/install-feature.sh"

uninstall_feature "$NAME"
