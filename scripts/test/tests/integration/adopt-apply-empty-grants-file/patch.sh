#!/usr/bin/env bash
# Patch: host commits an explicit but EMPTY .llm-wiki-adopt-grants.yml.
# This is the documented opt-out from the defaults: a host owner who
# really wants zero grants can author 'grants:' with no entries and
# adopt must honour that intent (no TOUCH applied).

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-empty-grants-file"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/empty-grants.git"

echo "# Empty Grants Host" > "$HOST/README.md"
echo "*.pyc"               > "$HOST/.gitignore"

cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
# host explicitly opts out of all grants (zero entries)
grants:
EOF

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host opts out via empty grants file"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1

echo "  adopt-apply-empty-grants-file patch applied: host at $HOST"
