#!/usr/bin/env bash
# Assertions: --apply --github-wiki against a host with a fake GitHub
# origin (URL resolves syntactically but no real wiki exists upstream).
# Seed-push must fail with 404; adopt captures the failure into
# github-wiki: failed, prints the workaround on stderr, and falls back to
# local init-wiki. Adopt exit 0.

STAGE="$SANDBOX/adopt-apply-github-wiki-fake-origin"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC_FILE="$STAGE/rc.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "adopt exited 0 (additive contract; seed-push failure is non-fatal)" \
    "[ \"\$(cat '$RC_FILE')\" = 0 ]"

# Manifest reports github-wiki: failed with the right diagnosis.
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest reports github-wiki: failed (seed-push 404)" \
    "grep -qF -- '- github-wiki: failed (seed-push 404' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest detail names the GitHub UI workaround step" \
    "grep -qF 'GitHub UI step required' '$HOST/.llm-wiki-adopt-log.md'"

# init-wiki ran in LOCAL mode (no --github flag forwarded).
assert "manifest reports init-wiki: applied" \
    "grep -qE '^- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"

# Stderr surfaces the workaround block.
assert "stderr contains the 'Wiki bootstrap via direct push failed' header" \
    "grep -qF 'Wiki bootstrap via direct push failed' '$ERR'"
assert "stderr names the wiki UI URL the user should open" \
    "grep -qF 'https://github.com/example-org-does-not-exist/fake-origin-host/wiki' '$ERR'"
assert "stderr names the re-run command pointing at adopt.sh (not instantiate.sh)" \
    "grep -qF 'bash scripts/adopt.sh --target=' '$ERR'"
assert "stderr instructs 'Click \"Create the first page\"'" \
    "grep -qF 'Create the first page' '$ERR'"
