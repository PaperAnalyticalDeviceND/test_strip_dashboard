#!/usr/bin/env bash
# Patch: virgin host with a merge grant, but the user passes
# --agent=none. Overlay setup should be skipped entirely and the merge
# TOUCH should be reported as 'skipped' (not applied via setup.sh, not
# failed). The host's CLAUDE.md is not a grant target and must survive
# byte-identical.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-agent-none"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/agent-none-host.git"

cat > "$HOST/CLAUDE.md" <<'EOF'
# Agent None Host

Host runs adopt with --agent=none. Overlay setup must NOT be invoked
and nothing may write to this host-owned file.

## Project conventions

These must survive unchanged.
EOF
echo "*.pyc" > "$HOST/.gitignore"

# The merge grant (depends on overlay) must record 'skipped' with the
# right reason.
mkdir -p "$HOST/.claude"
cat > "$HOST/.claude/settings.json" <<'EOF'
{"theme": "host"}
EOF
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  .claude/settings.json:  merge
EOF

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --agent=none --apply > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply --agent=none exited non-zero." >&2
fi

echo "  adopt-apply-agent-none patch applied: host at $HOST"
