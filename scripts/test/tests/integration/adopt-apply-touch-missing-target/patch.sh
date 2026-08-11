#!/usr/bin/env bash
# Patch: virgin host with the granted target ABSENT on disk. Exercises
# the absent-target TOUCH path: the grant is valid (target known, type
# known) but the file isn't there, so the apply path creates it from
# canonical via the overlay's setup.sh --hook.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-touch-missing-target"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/missing-target-host.git"

echo "# Missing Target Host" > "$HOST/README.md"
echo "*.pyc"                 > "$HOST/.gitignore"

# Host CLAUDE.md: purely host-authored background content. No grant
# covers CLAUDE.md anymore; adopt must leave it alone.
cat > "$HOST/CLAUDE.md" <<'EOF'
# Missing Target Host

Host-authored guidance. The grant under test is for
.claude/settings.json, which is intentionally NOT present on disk.
EOF

# Single grant targeting an absent file, keeping the fixture focused on
# the absent-target TOUCH path.
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  .claude/settings.json:  merge
EOF

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply exited non-zero." >&2
fi

echo "  adopt-apply-touch-missing-target patch applied: host at $HOST"
