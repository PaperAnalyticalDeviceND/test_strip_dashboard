#!/usr/bin/env bash
# Patch: virgin host with fake-github origin, run --apply --github-wiki
# --agent=none. The github-wiki sub-step is agent-orthogonal (the wiki is
# useful regardless of which agent consumes it), so the seed-push should
# still run and either succeed or fail with the 404 workaround. The
# overlay setup, in contrast, must skip and its merge
# TOUCH grants must report 'skipped (--agent=none, ...)'.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-github-wiki-agent-none"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org-fake/agent-none-gw-host.git"

echo "# Agent None GW Host" > "$HOST/README.md"
echo "*.pyc"                > "$HOST/.gitignore"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host for --github-wiki + --agent=none"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC=0
bash "$ADOPT" --target="$HOST" --apply --github-wiki --agent=none > "$OUT" 2> "$ERR" || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-apply-github-wiki-agent-none patch applied: host at $HOST (RC=$RC)"
