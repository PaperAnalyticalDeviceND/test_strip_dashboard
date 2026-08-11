#!/usr/bin/env bash
# Assertions: run adopt.sh --dry-run against a synthetic host repo and verify
# the ADD/SKIP/REFUSE classification.
#
# Fixture (built by patch.sh):
#   host repo with a fake origin (slug 'example-host'), host-authored files
#   (README, .gitignore, src/main.py), one byte-identical SKIP target
#   (llm-wiki.md), one host-modified REFUSE target
#   (wiki/agents/discipline-gates.md), and every other ADD allowlist path
#   absent so it gets reported as ADD.
#
# Hermetic: assertions inspect captured output and the host tree on disk;
# no network, no side effects beyond the sandbox.

STAGE="$SANDBOX/adopt-shape"
HOST="$STAGE/host"
OUT="$STAGE/adopt-output.txt"

# --- Output captured ---
assert "patch produced an output file" "[ -f '$OUT' ]"

# --- Header and identity ---
assert "prints dry-run banner" \
    "grep -qF 'adopt.sh --dry-run' '$OUT'"
assert "resolves identity from origin (example-host, not host basename)" \
    "grep -qF 'Resolved:         example-host' '$OUT'"
assert "header reports the grants file was detected" \
    "grep -qE 'Grants file:.*\\.llm-wiki-adopt-grants\\.yml \\(4 grant\\(s\\) found\\)' '$OUT'"

# --- ADD: forced-absent paths from the allowlist appear ---
# awk slices the ADD block ("ADD ..." line up to the next blank) so the
# greps below cannot accidentally match a path that lives in another section.
assert "ADD block lists wiki/init-wiki.sh" \
    "awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ wiki/init-wiki.sh'"
assert "ADD block lists scripts/lib/common.sh" \
    "awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ scripts/lib/common.sh'"
assert "ADD block lists scripts/update-from-template.sh" \
    "awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ scripts/update-from-template.sh'"
assert "ADD block lists wiki/.gitignore (the wiki ignore rule ships as a file)" \
    "awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ wiki/.gitignore'"
assert "ADD block does NOT list llm-wiki.md (it was a SKIP target)" \
    "! awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ llm-wiki.md'"
assert "ADD block does NOT list wiki/agents/discipline-gates.md (REFUSE target)" \
    "! awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ wiki/agents/discipline-gates.md'"

# --- SKIP: byte-identical copy detected ---
assert "SKIP block lists llm-wiki.md" \
    "awk '/^SKIP/,/^\$/' '$OUT' | grep -qF 'llm-wiki.md'"
assert "SKIP block does NOT list discipline-gates.md" \
    "! awk '/^SKIP/,/^\$/' '$OUT' | grep -qF 'discipline-gates.md'"

# --- REFUSE: host-modified file detected ---
assert "REFUSE block lists wiki/agents/discipline-gates.md (host-modified)" \
    "awk '/^REFUSE/,/^\$/' '$OUT' | grep -qF 'wiki/agents/discipline-gates.md'"
assert "REFUSE block does NOT list llm-wiki.md" \
    "! awk '/^REFUSE/,/^\$/' '$OUT' | grep -qF 'llm-wiki.md'"

# --- TOUCH classification ---
# .claude/settings.json is the only valid+present grant -> TOUCH block
# lists it with its merge operation and no absent marker.
assert "TOUCH block lists .claude/settings.json with merge mechanism" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qE '~ +\\.claude/settings\\.json +merge'"
assert "TOUCH row for .claude/settings.json does NOT show absent marker" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -q '\\.claude/settings\\.json.*\\[absent'"

# .gitignore is no longer a grant target -> INVALID, not TOUCH.
assert "TOUCH block does NOT list .gitignore (grant type retired)" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.gitignore'"
assert "GRANT WARNINGS section lists .gitignore as unknown" \
    "awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF '.gitignore' && \\
     awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'unknown grant target'"

# Makefile is unknown to the template -> INVALID, not TOUCH.
assert "TOUCH block does NOT list Makefile (unknown to template)" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF 'Makefile'"
assert "GRANT WARNINGS section lists Makefile as unknown" \
    "awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'Makefile' && \\
     awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'unknown grant target'"

# CLAUDE.md's managed-block grant is retired -> INVALID, not TOUCH.
# Regression case: hosts that still declare the pre-rules-files grant
# must be refused, not silently patched.
assert "TOUCH block does NOT list CLAUDE.md (managed-block grant retired)" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md'"
assert "GRANT WARNINGS section lists CLAUDE.md as unknown" \
    "awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md' && \\
     awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'unknown grant target'"

# --- Host-authored content untouched (no apply) ---
assert "host README.md preserved (still says 'Example Host')" \
    "grep -qF 'Example Host' '$HOST/README.md'"
assert "host .gitignore preserved" \
    "grep -qF '*.pyc' '$HOST/.gitignore'"
assert "host src/main.py preserved" \
    "grep -qF 'hello' '$HOST/src/main.py'"

# --- Virgin host: no 'already adopted' Status section ---
# This fixture has none of the adoption markers, so the dry-run must not
# emit a Status line. Counter-test for adopt-shape-adopted's positive case.
assert "no Status section emitted on virgin host" \
    "! grep -qE '^Status:.*already adopted' '$OUT'"

# --- Dry-run markers (no apply, no creep) ---
assert "dry-run announces no writes occurred" \
    "grep -qF 'Dry-run only. No files in' '$OUT'"
assert "NOT IMPLEMENTED YET section present" \
    "grep -qF 'NOT IMPLEMENTED YET' '$OUT'"

# --- No template-side files leaked into host (since dry-run does not apply) ---
assert "host did not gain wiki/init-wiki.sh" \
    "[ ! -e '$HOST/wiki/init-wiki.sh' ]"
assert "host did not gain scripts/lib/common.sh" \
    "[ ! -e '$HOST/scripts/lib/common.sh' ]"
