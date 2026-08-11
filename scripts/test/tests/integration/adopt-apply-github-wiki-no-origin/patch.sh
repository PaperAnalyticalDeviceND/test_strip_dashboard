#!/usr/bin/env bash
# Patch: virgin host WITHOUT a git remote 'origin' configured. Adopt with
# --apply --github-wiki should soft-skip the github-wiki sub-step (no URL
# to derive) and fall back to local init-wiki. Manifest must record the
# skip and adopt must exit 0 -- additive contract preserved.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-github-wiki-no-origin"
HOST="$STAGE/host"
mkdir -p "$HOST"

# Deliberately NO `git remote add origin ...` -- the absence is the test.
git init -q "$HOST"

echo "# No Origin Host" > "$HOST/README.md"
echo "*.pyc"            > "$HOST/.gitignore"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host without origin"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC=0
bash "$ADOPT" --target="$HOST" --apply --github-wiki > "$OUT" 2> "$ERR" || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-apply-github-wiki-no-origin patch applied: host at $HOST (RC=$RC)"
