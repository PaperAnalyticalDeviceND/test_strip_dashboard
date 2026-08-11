#!/usr/bin/env bash
# Patch: virgin host with a malformed .llm-wiki-adopt-grants.yml that
# mixes garbage lines, missing values, and one valid entry. The minimal
# YAML reader in adopt.sh should:
#   - skip lines it can't parse without crashing,
#   - still pick up the valid entry,
#   - not classify anything from the garbage lines.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-malformed-grants"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/malformed-host.git"

echo "# Malformed Host" > "$HOST/README.md"
echo "*.pyc"            > "$HOST/.gitignore"

# Malformed grants file:
#   - garbage prefix
#   - one well-formed entry (.claude/settings.json: merge)
#   - missing-value entries (key with no value)
#   - random non-grants prose
# adopt.sh's awk parser should pick up only the valid entry.
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
this is not yaml at all
grants:
  .claude/settings.json: merge
  CLAUDE.md:
  malformed line with no colon
  : value-without-key
trailing garbage at the bottom
EOF

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
RC=0
bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1 || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-apply-malformed-grants patch applied: host at $HOST"
