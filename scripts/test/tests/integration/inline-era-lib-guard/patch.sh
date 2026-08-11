#!/usr/bin/env bash
# Patch: fixture for the shared-lib guard (#92).
#
# Field case (onto-wiki, 2026-07-19): an inline-era host's run 1 delivers
# the current updater off the old inline list — which predates scripts/lib/
# — leaving an updater newer than its own dependencies. Run 2 then died at
# `source lib/common.sh` with a raw bash error and no guidance.
#
# Host shape mirrors the genuine post-run-1 state: current sync scripts,
# scripts/lib/ containing ONLY install-feature.sh (the one lib file that
# vintage shipped), a wiki dir, no manifest.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/inline-era-lib-guard"
H="$STAGE/host"
mkdir -p "$H/scripts/lib" "$H/wiki/bricked.wiki"
git init -q "$H"
: > "$H/wiki/bricked.wiki/SCHEMA_bricked.md"
cp "$TEMPLATE_ROOT/scripts/update-from-template.sh"   "$H/scripts/"
cp "$TEMPLATE_ROOT/scripts/check-template-version.sh" "$H/scripts/"
cp "$TEMPLATE_ROOT/scripts/lib/install-feature.sh"    "$H/scripts/lib/"

echo "  inline-era-lib-guard patch applied: host at $H"
