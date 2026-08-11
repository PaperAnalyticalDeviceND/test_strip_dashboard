#!/usr/bin/env bash
# Patch: stage a host and run adopt.sh --apply (Phase 1: ADD only).
#
# Verifies that ADD entries are actually written to the host tree
# (not just classified), that parent directories are created, that the
# manifest file .llm-wiki-adopt-log.md is written, that SKIP/REFUSE
# entries are still respected (no overwrite), and that re-running
# --apply is idempotent at the file level (no second-write churn on
# files that are now byte-equal).

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-add"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/apply-host.git"

# Host-authored tree.
echo "# Apply Host"  > "$HOST/README.md"
echo "*.pyc"         > "$HOST/.gitignore"

# Pre-stage:
#   - one SKIP target (byte-equal to template) -> apply must leave it alone
#   - one REFUSE target (different content)    -> apply must NOT overwrite
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"
mkdir -p "$HOST/wiki/agents"
echo "# Host-modified discipline-gates — must survive --apply" \
    > "$HOST/wiki/agents/discipline-gates.md"

# Commit everything so the working tree is clean (the safety guard
# refuses --apply on a dirty tree).
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"

# --- First --apply run ---
OUTFILE="$STAGE/apply-run1.txt"
if ! bash "$ADOPT" --target="$HOST" --apply > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh --apply exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

# --- Second --apply run (idempotency check) ---
# Commit what the first run produced so the tree is clean again, then re-run.
# A second --apply should see all previously-ADDed paths as SKIP (byte-equal)
# and write zero new files.
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "after first apply"

# Second --apply uses --force because after the first apply, the host
# now satisfies the composite adoption detector (>= 2 of 3 signals).
# Without --force, adopt would advise to use update-from-template.sh.
# The --force flag here keeps the historical idempotency test alive.
OUTFILE2="$STAGE/apply-run2.txt"
if ! bash "$ADOPT" --target="$HOST" --apply --force > "$OUTFILE2" 2>&1; then
    echo "  WARN: second adopt.sh --apply --force exited non-zero." >&2
    sed 's/^/    /' "$OUTFILE2" >&2
fi

# Third --apply WITHOUT --force exercises the new advisory abort.
OUTFILE3="$STAGE/apply-run3-noforce.txt"
NOFORCE_RC=0
bash "$ADOPT" --target="$HOST" --apply > "$OUTFILE3" 2>&1 || NOFORCE_RC=$?
# Manifest is now appended by the run2 --force apply, so the tree is dirty
# again. Commit so the run3 (no --force) exits on the adoption check, not
# on the dirty-tree check (we want to test the adoption-detect path).
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "after second apply" \
    >/dev/null 2>&1 || true
bash "$ADOPT" --target="$HOST" --apply > "$OUTFILE3" 2>&1 || NOFORCE_RC=$?
echo "$NOFORCE_RC" > "$STAGE/noforce-rc.txt"

echo "  adopt-apply-add patch applied: host at $HOST"
