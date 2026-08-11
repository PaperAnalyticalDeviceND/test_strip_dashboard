#!/usr/bin/env bash
# Patch: virgin host with fake-github origin, run --github-wiki WITHOUT
# --apply. The dry-run preview block should run read-only probes and
# emit a GITHUB WIKI section reporting the prospective status. Nothing
# must be mutated -- no manifest written, no files created in the host.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-dryrun-github-wiki"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org-fake/dryrun-gw-host.git"

echo "# Dry-run GW Host" > "$HOST/README.md"
echo "*.pyc"             > "$HOST/.gitignore"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host for dry-run preview"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/dryrun-output.txt"
ERR="$STAGE/dryrun-stderr.txt"
RC=0
# Deliberately NO --apply. Expect dry-run.
bash "$ADOPT" --target="$HOST" --github-wiki > "$OUT" 2> "$ERR" || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-dryrun-github-wiki patch applied: host at $HOST (RC=$RC)"
