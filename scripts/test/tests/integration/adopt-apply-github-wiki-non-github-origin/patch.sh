#!/usr/bin/env bash
# Patch: virgin host with origin pointing at a non-GitHub host (GitLab in
# this case). Adopt's --github-wiki dispatch must detect the non-github
# host BEFORE calling lw_wiki_url (which dies loud on non-GitHub) and
# soft-skip with a clear status. Local init-wiki still runs. Exit 0.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-github-wiki-non-github-origin"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
# Non-GitHub origin (SSH form, gitlab.com host).
git -C "$HOST" remote add origin "git@gitlab.com:example-group/non-github-host.git"

echo "# Non GitHub Host" > "$HOST/README.md"
echo "*.pyc"             > "$HOST/.gitignore"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host with gitlab origin"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC=0
bash "$ADOPT" --target="$HOST" --apply --github-wiki > "$OUT" 2> "$ERR" || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-apply-github-wiki-non-github-origin patch applied: host at $HOST (RC=$RC)"
