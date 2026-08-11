#!/usr/bin/env bash
# Patch: stage a VIRGIN host (composite < 2 of 3 signals) that already
# has its own CLAUDE.md. This exercises the realistic case "project has
# its own CLAUDE.md and wants to take on the wiki-memory pattern".
#
# adopt --apply on this host should:
#   - run Phase 1 ADD (host has none of the template files; the
#     behavioral instructions land as .claude/rules/*.md)
#   - run Phase 2B init-wiki (creates wiki sub-repo)
#   - run Phase 2B overlay setup
#   - leave the host's CLAUDE.md byte-identical (no grant covers it;
#     nothing writes to it)
#
# No --force needed; the host starts as virgin.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-virgin-with-claude"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/virgin-claude-host.git"

# Host-authored content. The whole CLAUDE.md must survive adoption
# byte-identical; the snapshot below is what the assertions compare
# against after both the apply and the re-run.
cat > "$HOST/README.md" <<'EOF'
# Virgin Claude Host
A project that has its own CLAUDE.md and is taking on the wiki pattern.
EOF

cat > "$HOST/CLAUDE.md" <<'EOF'
# Virgin Claude Host

This CLAUDE.md was authored by the project owner before adoption.
It has its own conventions, style notes, and project-specific rules.

## Project conventions

These conventions are host-authored and must survive adoption unchanged.
EOF

echo "*.pyc" > "$HOST/.gitignore"

# Snapshot for the byte-identity assertions.
cp "$HOST/CLAUDE.md" "$STAGE/claude-md.before"

# No grants file: the defaults path (one merge grant) is exercised
# elsewhere; this fixture is about the host-owned files surviving a
# full virgin adopt.

# Crucially: do NOT stage llm-wiki.md, discipline-gates.md, or
# wiki/init-wiki.sh. That keeps the composite detector at 0 of 3 so
# adopt sees this as a virgin host and proceeds with --apply.

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply exited non-zero." >&2
    sed 's/^/    /' "$OUT" >&2
fi

echo "  adopt-apply-virgin-with-claude patch applied: host at $HOST"
