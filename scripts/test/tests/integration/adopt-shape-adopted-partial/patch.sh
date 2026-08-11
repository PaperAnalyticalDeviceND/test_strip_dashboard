#!/usr/bin/env bash
# Patch: stage a host that hits exactly the 2-of-3 threshold for composite
# adoption detection. Companion to adopt-shape-adopted (3-of-3): this
# fixture proves that the count reported by the Status line is genuinely
# dynamic (computed from the actual signals) rather than hardcoded against
# the 3-of-3 case the other fixture exercises.
#
# Signals staged:
#   A: llm-wiki.md byte-identical to template                       -> present
#   B: wiki/agents/discipline-gates.md byte-identical to template   -> absent
#      (fixture deliberately omits this file so Signal B fails)
#   C: wiki/init-wiki.sh present                                    -> present
#
# Result: 2 of 3 signals -> threshold met -> Status fires with
# '2 of 3 indicators matched', and signal B's bullet is absent from the
# Status block.
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-shape-adopted-partial"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/partial-host.git"

# Host-authored content (must survive untouched).
echo "# Partial Host"        > "$HOST/README.md"
echo "*.pyc"                 > "$HOST/.gitignore"

# Signal A: llm-wiki.md byte-identical to template.
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"

# Signal B intentionally OFF: the host does NOT have a copy of
# wiki/agents/discipline-gates.md. Simulates a partial adoption / partial
# template drift where the host has the root pattern but never sync'd the
# shared overlay-agnostic files. (Host owns its own CLAUDE.md without any
# pattern markers — included to verify adopt does not depend on it.)
cat > "$HOST/CLAUDE.md" <<'EOF'
# Partial Host

This CLAUDE.md is entirely host-authored. The agent overlay was either
skipped at instantiation or this repo predates the wiki-pattern overlay.

Project description, conventions, and notes for the LLM go here.
EOF

# Signal C: wiki/init-wiki.sh present (host-modified -> doubles as REFUSE
# target, same pattern as the 3-of-3 fixture).
mkdir -p "$HOST/wiki"
echo "# Host-modified init-wiki.sh — diverged from template" \
    > "$HOST/wiki/init-wiki.sh"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUTFILE="$STAGE/adopt-output.txt"

if ! bash "$ADOPT" --target="$HOST" > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

echo "  adopt-shape-adopted-partial patch applied: host at $HOST, output at $OUTFILE"
