#!/usr/bin/env bash
# Patch: stage a host that the composite detector marks as already adopted
# (>= 2 of 3 signals) and run adopt.sh --apply WITHOUT --force. Expected
# behaviour: adopt detects the adoption, exits non-zero, and prints an
# advisory routing the host owner to scripts/update-from-template.sh.
# Nothing is written to the host tree.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-blocked"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/blocked-host.git"

# Host content (kept around to verify it survives the failed --apply).
echo "# Blocked Host"     > "$HOST/README.md"
echo "*.pyc"              > "$HOST/.gitignore"

# Stage Signals A and C so composite >= 2 of 3 -> 'already adopted'.
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"
mkdir -p "$HOST/wiki"
cp "$TEMPLATE_ROOT/wiki/init-wiki.sh" "$HOST/wiki/init-wiki.sh"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial adopted-looking host"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
RC=0
bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1 || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-apply-blocked patch applied: host at $HOST, output at $OUT (RC=$RC)"
