#!/usr/bin/env bash
# Patch: stage a tiny fake "host" tree under $SANDBOX/manifest-shape so the
# assertions can exercise lw_manifest_assemble_active_files in both detection
# modes (host has .claude/ overlay vs not) without polluting the real
# template root.

set -uo pipefail

ROOT="$SANDBOX/manifest-shape"
mkdir -p "$ROOT/host-with-claude/.claude"
mkdir -p "$ROOT/host-with-cursor/.cursor"
mkdir -p "$ROOT/host-bare"

echo "  manifest-shape patch applied: fixtures at $ROOT"
