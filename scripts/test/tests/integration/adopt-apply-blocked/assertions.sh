#!/usr/bin/env bash
# Assertions: adopt.sh --apply (without --force) against an already-adopted
# host exits non-zero with the advisory message and writes nothing.

STAGE="$SANDBOX/adopt-apply-blocked"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
RC_FILE="$STAGE/rc.txt"

# --- Exit code is non-zero (signals the advisory abort) ---
assert "adopt --apply on adopted host exits non-zero" \
    "[ \"\$(cat '$RC_FILE')\" != 0 ]"

# --- Advisory message contents ---
assert "advisory names the situation: 'already adopted'" \
    "grep -qF 'this repo has already adopted' '$OUT'"
assert "advisory states adopt is for first-time adoption only" \
    "grep -qF 'first-time adoption only' '$OUT'"
assert "advisory lists the detected indicators count" \
    "grep -qE '2 of 3 indicators' '$OUT'"
assert "advisory lists each matched signal as a bullet" \
    "grep -qF -- '- llm-wiki.md byte-identical to template' '$OUT'"
assert "advisory routes to scripts/update-from-template.sh" \
    "grep -qF 'bash scripts/update-from-template.sh' '$OUT'"
assert "advisory mentions --force as the escape hatch" \
    "grep -qF -- '--force' '$OUT'"

# --- Host tree untouched (no ADD, no init-wiki, no overlay setup) ---
assert "host did not gain wiki/agents/discipline-gates.md" \
    "[ ! -e '$HOST/wiki/agents/discipline-gates.md' ]"
assert "host did not gain scripts/lib/common.sh" \
    "[ ! -e '$HOST/scripts/lib/common.sh' ]"
assert "host did not gain wiki/blocked-host.wiki/" \
    "[ ! -d '$HOST/wiki/blocked-host.wiki' ]"
assert "no manifest written (.llm-wiki-adopt-log.md absent)" \
    "[ ! -f '$HOST/.llm-wiki-adopt-log.md' ]"

# --- Host content preserved ---
assert "host README preserved" "grep -qF 'Blocked Host' '$HOST/README.md'"
assert "host .gitignore preserved (no sentinel block injected)" \
    "! grep -qF '<!-- lw:wiki-rules -->' '$HOST/.gitignore'"
