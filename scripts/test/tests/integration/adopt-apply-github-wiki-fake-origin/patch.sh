#!/usr/bin/env bash
# Patch: virgin host with origin pointing at a github.com URL that resolves
# syntactically (so the host check passes and the wiki URL is derived) but
# does not have a real wiki materialized on GitHub. The seed-push therefore
# 404s, exercising the most common real-world failure path. Adopt must
# capture the failure in github-wiki: failed, print the workaround on
# stderr, and fall back to local init-wiki. Exit 0 (additive contract).

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-github-wiki-fake-origin"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
# Fake GitHub URL: org/name don't exist. ls-remote will return non-zero
# AND the seed-push will hit auth-required-then-404. Both signal "wiki not
# materialized" to the dispatch.
git -C "$HOST" remote add origin "https://github.com/example-org-does-not-exist/fake-origin-host.git"

echo "# Fake Origin Host" > "$HOST/README.md"
echo "*.pyc"              > "$HOST/.gitignore"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host with fake github origin"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC=0
bash "$ADOPT" --target="$HOST" --apply --github-wiki > "$OUT" 2> "$ERR" || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-apply-github-wiki-fake-origin patch applied: host at $HOST (RC=$RC)"
