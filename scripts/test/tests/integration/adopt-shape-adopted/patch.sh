#!/usr/bin/env bash
# Patch: stage a host repo that has ALREADY adopted the wiki pattern, to
# exercise adopt.sh's composite 'already adopted' detection and the Status
# advice it surfaces.
#
# Detection uses three harness-agnostic signals (>= 2 of 3 -> adopted):
#   A: llm-wiki.md byte-identical to template
#   B: wiki/agents/discipline-gates.md byte-identical to template
#   C: wiki/init-wiki.sh present in target
# This fixture deliberately stages all three so the report exercises the
# full Status block (3 of 3 indicators).
#
# It also stages a .claude/ directory so the overlay-detection metadata
# block reports 'Overlay(s) detected: claude-code' — independent of the
# adoption decision; verifies the catalog-style overlay lookup.
#
# The host-modified wiki/init-wiki.sh doubles as a REFUSE entry: the
# Status advice's reference to 'REFUSE entries below' is concretely
# demonstrated in the same report.
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-shape-adopted"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/adopted-host.git"

# Host-authored content (must survive untouched).
echo "# Adopted Host"        > "$HOST/README.md"
echo "*.pyc"                 > "$HOST/.gitignore"

# --- Signal A: llm-wiki.md byte-identical to template ---
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"

# --- Signal B: wiki/agents/discipline-gates.md byte-identical to template ---
# Harness-agnostic shared file (TEMPLATE_SHARED_INFRA), present regardless of
# overlay choice. Replaces the previous Claude-only CLAUDE.md sentinel
# signal so detection works for cursor / gemini / --agent=none too.
mkdir -p "$HOST/wiki/agents"
cp "$TEMPLATE_ROOT/wiki/agents/discipline-gates.md" \
    "$HOST/wiki/agents/discipline-gates.md"

# --- Signal C: wiki/init-wiki.sh present (and host-modified -> REFUSE) ---
# Doubles as the REFUSE target so the Status advice's "REFUSE entries
# below mark places where overwriting would discard local changes" is
# concretely demonstrated in the same report.
echo "# Host-modified init-wiki.sh — do not let update-from-template silently overwrite" \
    > "$HOST/wiki/init-wiki.sh"

# --- Overlay metadata (informational, not a detection signal) ---
# Host has a .claude/ directory -> 'Overlay(s) detected: claude-code'
# in the Status block. Exercises the catalog-style overlay lookup.
mkdir -p "$HOST/.claude/commands"
echo "# Host's own claude overlay commands" > "$HOST/.claude/commands/example.md"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUTFILE="$STAGE/adopt-output.txt"

if ! bash "$ADOPT" --target="$HOST" > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

echo "  adopt-shape-adopted patch applied: host at $HOST, output at $OUTFILE"
