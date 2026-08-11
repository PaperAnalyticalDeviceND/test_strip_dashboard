#!/usr/bin/env bash
# Assertions: dry-run with --github-wiki against a virgin host with a
# fake-github origin runs read-only probes and emits a GITHUB WIKI
# preview section. The host must not be touched: no manifest, no ADD
# files copied, no .gitignore mutation, no .claude/ directory.

STAGE="$SANDBOX/adopt-dryrun-github-wiki"
HOST="$STAGE/host"
OUT="$STAGE/dryrun-output.txt"
ERR="$STAGE/dryrun-stderr.txt"
RC_FILE="$STAGE/rc.txt"

assert "dry-run produced output" "[ -f '$OUT' ]"
assert "dry-run exited 0" \
    "[ \"\$(cat '$RC_FILE')\" = 0 ]"

# Header confirms dry-run mode.
assert "header banner says 'adopt.sh --dry-run' (not --apply)" \
    "grep -qF 'adopt.sh --dry-run' '$OUT'"

# GITHUB WIKI section is emitted (because --github-wiki was passed).
assert "GITHUB WIKI section present" \
    "grep -qF 'GITHUB WIKI (--github-wiki preview; read-only)' '$OUT'"

# Status line within the preview block.
assert "GITHUB WIKI section reports would-apply (wiki not yet materialized)" \
    "awk '/^GITHUB WIKI/,/^\$/' '$OUT' | grep -q 'would-apply.*seed-push to https://github.com/example-org-fake/dryrun-gw-host.wiki.git'"

# Read-only -- the host must not be touched.
assert "manifest NOT written (dry-run does not mutate)" \
    "[ ! -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "no template files copied to host (llm-wiki.md absent)" \
    "[ ! -f '$HOST/llm-wiki.md' ]"
assert "no wiki sub-repo created" \
    "[ ! -d '$HOST/wiki' ]"
assert ".claude/ directory NOT created" \
    "[ ! -d '$HOST/.claude' ]"
assert "host .gitignore preserved exactly (no wiki rule added in dry-run)" \
    "! grep -qF 'wiki/*.wiki/' '$HOST/.gitignore'"
assert "host .gitignore preserves preexisting *.pyc rule" \
    "grep -qFx '*.pyc' '$HOST/.gitignore'"

# Dry-run never prints the 404 workaround block (that only runs in apply).
assert "stderr does NOT contain the 404 workaround block" \
    "! grep -qF 'Wiki bootstrap via direct push failed' '$ERR'"

# The 'Dry-run only' epilogue is present.
assert "output ends with 'Dry-run only' notice" \
    "grep -qF 'Dry-run only. No files in' '$OUT'"
