#!/usr/bin/env bash
# Patch: virgin host with a directory blocker placed where an ADD entry
# wants to land. cp -p will fail for paths under the blocker. Verifies
# adopt captures cp / mkdir -p RC and records the failure in
# FAILED_ADDS rather than silently claiming success in APPLIED_ADDS.
#
# Reported by Chris Sweet against PR #51 (item #1): adopt.sh:515-523
# unconditionally APPLIED_ADDS+=("$path") after an unchecked cp -p, so
# a cp failure would land in the manifest as success.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-add-failure"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/add-failure-host.git"

echo "# Add Failure Host" > "$HOST/README.md"
echo "*.pyc"              > "$HOST/.gitignore"

# Block the wiki/agents/claude-code/ directory by pre-creating it as a
# REGULAR FILE. Five overlay templates land under wiki/agents/claude-code/
# in the manifest ADD set (TEMPLATE_OVERLAY_CLAUDE). Their parent dirs
# cannot be mkdir'd; cp fails.
# Block scripts/lib/ the same way to hit a second category.
mkdir -p "$HOST/wiki/agents"
echo "blocker (regular file, not directory)" > "$HOST/wiki/agents/claude-code"
mkdir -p "$HOST/scripts"
echo "blocker" > "$HOST/scripts/lib"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host with directory blockers"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
RC=0
bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1 || RC=$?
echo "$RC" > "$STAGE/rc.txt"

echo "  adopt-apply-add-failure patch applied: host at $HOST (RC=$RC)"
