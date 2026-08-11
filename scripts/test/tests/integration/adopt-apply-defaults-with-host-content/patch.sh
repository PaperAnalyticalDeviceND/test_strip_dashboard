#!/usr/bin/env bash
# Patch: host has CLAUDE.md, .gitignore, AND .claude/settings.json all
# pre-authored, but no grants file. Default-grants path must classify
# the three as TOUCH (was_absent=0) and the apply path must MODIFY
# them (preserving host content), not 'create from canonical'.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-defaults-with-host-content"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/defaults-host-content.git"

cat > "$HOST/CLAUDE.md" <<'EOF'
# Defaults With Host Content
Host-authored guidance that must survive adoption.

### Knowledge Graph
(host has the KG anchor)
EOF

cat > "$HOST/.gitignore" <<'EOF'
*.pyc
__pycache__/
*.npz
EOF

mkdir -p "$HOST/.claude"
cat > "$HOST/.claude/settings.json" <<'EOF'
{
  "theme": "host",
  "permissions": { "allow": ["Bash"] }
}
EOF

# Deliberately NO .llm-wiki-adopt-grants.yml.

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "host with all three integration files preauthored"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1

echo "  adopt-apply-defaults-with-host-content patch applied: host at $HOST"
