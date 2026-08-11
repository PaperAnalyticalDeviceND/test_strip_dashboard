#!/usr/bin/env bash
# Assertions: --apply --github-wiki against a host without origin must
# soft-skip the github-wiki sub-step. Adopt's additive contract requires
# that init-wiki still runs (locally, no --github), the manifest records
# both statuses, and adopt exits 0. The seed-push must NOT run (so no 404
# fallback message on stderr).

STAGE="$SANDBOX/adopt-apply-github-wiki-no-origin"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC_FILE="$STAGE/rc.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "adopt exited 0 (additive contract)" \
    "[ \"\$(cat '$RC_FILE')\" = 0 ]"

# Manifest reports github-wiki: skipped with the right reason.
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest reports github-wiki: skipped (no origin)" \
    "grep -qF -- '- github-wiki: skipped (no origin remote on target' '$HOST/.llm-wiki-adopt-log.md'"

# init-wiki still ran locally (without --github).
assert "manifest reports init-wiki: applied" \
    "grep -qE '^- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest init-wiki detail does NOT include --github flag" \
    "! grep -qF '\\-\\-github' '$HOST/.llm-wiki-adopt-log.md'"

# Stderr must NOT contain the 404 workaround block (no seed-push attempted).
assert "stderr does NOT contain the GitHub Wiki 404 workaround block" \
    "! grep -qF 'Wiki bootstrap via direct push failed' '$ERR'"
assert "stderr does NOT mention Create the first page" \
    "! grep -qF 'Create the first page' '$ERR'"
