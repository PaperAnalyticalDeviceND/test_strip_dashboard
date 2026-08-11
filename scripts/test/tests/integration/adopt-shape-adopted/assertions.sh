#!/usr/bin/env bash
# Assertions: adopt.sh against a host that has already adopted the wiki
# pattern (three composite signals present, threshold met). Verifies the
# composite detection, the Status block content, and that the advice is
# honest about update-from-template's overwrite semantics and how it
# relates to the REFUSE entries below.

STAGE="$SANDBOX/adopt-shape-adopted"
HOST="$STAGE/host"
OUT="$STAGE/adopt-output.txt"

# --- Output captured ---
assert "patch produced an output file" "[ -f '$OUT' ]"
assert "resolves identity from origin (adopted-host)" \
    "grep -qF 'Resolved:         adopted-host' '$OUT'"

# --- Status section: composite detection fired with all 3 signals ---
assert "Status line announces 'already adopted'" \
    "grep -qE '^Status:.*already adopted' '$OUT'"
assert "Status line reports the indicator count (3 of 3)" \
    "grep -qF '3 of 3 indicators matched' '$OUT'"
assert "Status block lists signal A: llm-wiki.md byte-identical" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'llm-wiki.md byte-identical to template'"
assert "Status block lists signal B: wiki/agents/discipline-gates.md byte-identical" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'wiki/agents/discipline-gates.md byte-identical to template'"
assert "Status block lists signal C: wiki/init-wiki.sh present" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'wiki/init-wiki.sh present'"

# --- Overlay metadata (catalog lookup; informational, not a signal) ---
assert "Overlay metadata line reports claude-code (from .claude/ presence)" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'Overlay(s) detected: claude-code'"
assert "Overlay metadata does NOT report cursor (host has no .cursor/)" \
    "! awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'cursor'"

# --- Advice: route + semantic caveat (Path 1) ---
assert "advice routes to scripts/update-from-template.sh" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'scripts/update-from-template.sh'"
assert "advice names the OVERWRITES gotcha explicitly" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'OVERWRITES'"
assert "advice cites the REFUSE entries below as the concrete risk" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'REFUSE entries'"
assert "advice tells the host owner to review before running update" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'review'"

# --- The advice's claim about REFUSE entries is non-vacuous ---
# Fixture pre-staged wiki/init-wiki.sh with different content; adopt must
# classify it as REFUSE so the Status advice ('REFUSE entries below') is
# truthful for this host, not just rhetorically present.
assert "REFUSE block lists wiki/init-wiki.sh (the advice's concrete referent)" \
    "awk '/^REFUSE/,/^\$/' '$OUT' | grep -qF 'wiki/init-wiki.sh'"

# --- Negative: Status appears ONCE, not duplicated ---
status_count=$(grep -cE '^Status:.*already adopted' "$OUT" || true)
assert "Status line appears exactly once (not duplicated)" \
    "[ '$status_count' -eq 1 ]"

# --- Dry-run still doesn't apply ---
assert "host README.md preserved" \
    "grep -qF 'Adopted Host' '$HOST/README.md'"
assert "host's own .claude/ overlay preserved (no churn from adopt)" \
    "[ -f '$HOST/.claude/commands/example.md' ]"
assert "host kept its own init-wiki.sh content" \
    "grep -qF 'do not let update-from-template silently overwrite' '$HOST/wiki/init-wiki.sh'"
assert "dry-run announces no writes occurred" \
    "grep -qF 'Dry-run only. No files in' '$OUT'"
