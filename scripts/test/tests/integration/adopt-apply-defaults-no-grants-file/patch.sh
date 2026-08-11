#!/usr/bin/env bash
# Patch: virgin host, no grants file. Expected behaviour (option D):
# adopt classifies the one standard grant (.claude/settings.json merge)
# automatically and applies it, so the host gets a fully-functional
# wiki-memory adoption without hand-authoring YAML.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-defaults-no-grants-file"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/defaults-no-file.git"

echo "# Defaults No-File Host" > "$HOST/README.md"
echo "*.pyc"                   > "$HOST/.gitignore"

# Deliberately NO .llm-wiki-adopt-grants.yml.

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host without grants file"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1

echo "  adopt-apply-defaults-no-grants-file patch applied: host at $HOST"
