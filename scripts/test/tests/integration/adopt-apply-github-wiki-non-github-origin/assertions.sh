#!/usr/bin/env bash
# Assertions: --apply --github-wiki against a host whose origin points at
# a non-GitHub host (gitlab.com). The dispatch's inline host check must
# catch this BEFORE lw_wiki_url runs (which would otherwise lw_die and
# crash the entire script). Soft-skip with the non-github host detail;
# init-wiki falls back to local. Adopt exit 0.

STAGE="$SANDBOX/adopt-apply-github-wiki-non-github-origin"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC_FILE="$STAGE/rc.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "adopt exited 0 (lw_die was NOT triggered; soft-skip worked)" \
    "[ \"\$(cat '$RC_FILE')\" = 0 ]"

# Manifest reports github-wiki: skipped with the non-github detail.
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest reports github-wiki: skipped (non-github host)" \
    "grep -qF -- \"- github-wiki: skipped (non-github host 'gitlab.com')\" '$HOST/.llm-wiki-adopt-log.md'"

# init-wiki ran locally (without --github).
assert "manifest reports init-wiki: applied (local fallback)" \
    "grep -qE '^- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"

# Stderr must NOT contain lw_die output (which would indicate lw_wiki_url was called).
assert "stderr does NOT contain lw_die error from lw_wiki_url" \
    "! grep -qF 'GitHub-only' '$ERR'"
assert "stderr does NOT contain the 404 workaround block (no seed-push attempted)" \
    "! grep -qF 'Wiki bootstrap via direct push failed' '$ERR'"
