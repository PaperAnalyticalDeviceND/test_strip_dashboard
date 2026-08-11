#!/usr/bin/env bash
# Assertions: adopt.sh against a host that hits exactly the 2-of-3 composite
# threshold. The point of this test is to prove the count reported by the
# Status line is genuinely dynamic (computed from real signals) rather than
# hardcoded against the 3-of-3 case. Without this fixture, hardcoding
# '3 of 3' would pass the adopt-shape-adopted suite — verified by mutation.

STAGE="$SANDBOX/adopt-shape-adopted-partial"
HOST="$STAGE/host"
OUT="$STAGE/adopt-output.txt"

# --- Output captured ---
assert "patch produced an output file" "[ -f '$OUT' ]"
assert "resolves identity from origin (partial-host)" \
    "grep -qF 'Resolved:         partial-host' '$OUT'"

# --- Status section: 2-of-3 threshold met, count is the load-bearing fact ---
assert "Status line announces 'already adopted'" \
    "grep -qE '^Status:.*already adopted' '$OUT'"
# Load-bearing assertion: forces the reported count to be EXACTLY 2 here.
# Hardcoding '3 of 3' anywhere in adopt.sh fails this; the count must come
# from $ADOPTION_COUNT.
assert "Status line reports the indicator count (2 of 3, not 3 of 3)" \
    "grep -qF '2 of 3 indicators matched' '$OUT'"
assert "Status line does NOT claim 3 of 3 (guard against hardcoded count)" \
    "! grep -qF '3 of 3 indicators matched' '$OUT'"

# --- Each present signal listed; absent signal NOT listed ---
assert "Status block lists signal A: llm-wiki.md byte-identical" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'llm-wiki.md byte-identical to template'"
assert "Status block lists signal C: wiki/init-wiki.sh present" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'wiki/init-wiki.sh present'"
assert "Status block does NOT list signal B (host has no wiki/agents/discipline-gates.md)" \
    "! awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'wiki/agents/discipline-gates.md byte-identical'"

# --- Overlay metadata: host has no .claude/ or .cursor/ -> none ---
assert "Overlay metadata line reports 'none' when host has no overlay" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'Overlay(s) detected: none'"

# --- Advice block follows (same shape as the 3-of-3 case) ---
assert "advice routes to scripts/update-from-template.sh" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'scripts/update-from-template.sh'"
assert "advice names the OVERWRITES gotcha explicitly" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'OVERWRITES'"
assert "advice cites the REFUSE entries below" \
    "awk '/^Status:/,/^\$/' '$OUT' | grep -qF 'REFUSE entries'"

# --- The advice's claim about REFUSE entries is non-vacuous ---
assert "REFUSE block lists wiki/init-wiki.sh" \
    "awk '/^REFUSE/,/^\$/' '$OUT' | grep -qF 'wiki/init-wiki.sh'"

# --- Host content untouched ---
assert "host README.md preserved" \
    "grep -qF 'Partial Host' '$HOST/README.md'"
assert "host CLAUDE.md preserved (host prose still there)" \
    "grep -qF 'entirely host-authored' '$HOST/CLAUDE.md'"
assert "host kept its own init-wiki.sh content" \
    "grep -qF 'diverged from template' '$HOST/wiki/init-wiki.sh'"
