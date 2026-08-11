#!/usr/bin/env bash
# Assertions: adopt --apply on a virgin host that already has its own
# CLAUDE.md. Verifies the host-owned contract: adopt runs end-to-end
# (ADD + init-wiki + overlay setup) and the host's CLAUDE.md comes
# through byte-identical -- the behavioral instructions arrive as the
# ADDed .claude/rules/*.md files instead of injected blocks.

STAGE="$SANDBOX/adopt-apply-virgin-with-claude"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

# --- Apply succeeded (no advisory abort, no errors) ---
assert "apply produced an output file" "[ -f '$OUT' ]"
assert "apply did NOT emit the 'already adopted' advisory (host was virgin)" \
    "! grep -qF 'already adopted the wiki-memory pattern' '$OUT'"
assert "apply reports the Applied: N file(s) summary" \
    "grep -qE 'Applied: [0-9]+ file\\(s\\) created' '$OUT'"

# --- Host CLAUDE.md byte-identical through the whole adopt ---
assert "host CLAUDE.md is byte-identical to its pre-adopt snapshot" \
    "cmp -s '$STAGE/claude-md.before' '$HOST/CLAUDE.md'"
assert "host CLAUDE.md gained NO lw sentinels" \
    "! grep -qF '<!-- lw:' '$HOST/CLAUDE.md'"

# --- Behavioral instructions arrived as ADDed rule files ---
assert ".claude/rules/wiki-as-memory.md was ADDed" \
    "[ -f '$HOST/.claude/rules/wiki-as-memory.md' ]"
assert ".claude/rules/memory-boundary.md was ADDed" \
    "[ -f '$HOST/.claude/rules/memory-boundary.md' ]"

# --- Manifest reflects the retired grant and the applied phases ---
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest does NOT list a CLAUDE.md TOUCH (managed-block grant retired)" \
    "! grep -qF -- '- CLAUDE.md (' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records init-wiki as applied (first run on virgin host)" \
    "grep -qF -- '- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records overlay setup as applied" \
    "grep -qF -- '- overlay setup: applied' '$HOST/.llm-wiki-adopt-log.md'"

# --- Wiki sub-repo was created by init-wiki ---
assert "wiki sub-repo created at wiki/virgin-claude-host.wiki/" \
    "[ -d '$HOST/wiki/virgin-claude-host.wiki/.git' ]"

# --- After --apply, composite detector should now see this host as adopted ---
# Re-running --apply (no --force) should fire the advisory. Need to commit
# everything first to keep the working tree clean (the wiki sub-repo embeds
# its own .git inside the host; --add ignores its contents but the entry
# itself counts).
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A 2>/dev/null
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "after apply" \
    >/dev/null 2>&1 || true
ADOPT_ABS="$(cd "$HERE/.." && pwd)/adopt.sh"
RERUN_OUT="$STAGE/rerun.txt"
RERUN_RC=0
bash "$ADOPT_ABS" --target="$HOST" --apply > "$RERUN_OUT" 2>&1 || RERUN_RC=$?
assert "re-running --apply on the now-adopted host exits non-zero" \
    "[ '$RERUN_RC' -ne 0 ]"
assert "re-running --apply on the now-adopted host fires the advisory" \
    "grep -qF 'already adopted the wiki-memory pattern' '$RERUN_OUT'"
assert "host CLAUDE.md still byte-identical after the advisory re-run" \
    "cmp -s '$STAGE/claude-md.before' '$HOST/CLAUDE.md'"
