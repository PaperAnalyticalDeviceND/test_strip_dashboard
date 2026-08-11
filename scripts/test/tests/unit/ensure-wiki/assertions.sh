#!/usr/bin/env bash
# Assertions: ensure-wiki.py identity, GitHub-only scope, output contract, and
# the staging+rename clone mechanics (partial-clone and concurrency safety).
#
# Hook output is captured to FILES, never inlined into assert command strings:
# the nudge text contains backticks, and the assert helper eval's its argument,
# so an inlined value would trigger command substitution and corrupt the check.

STAGE="$SANDBOX/ensure-wiki"
REPO_ROOT_EW="$(cd "$HERE/../.." && pwd)"
HOOK="$REPO_ROOT_EW/wiki/agents/claude-code/templates/ensure-wiki.py"

if ! command -v python3 >/dev/null 2>&1; then
    skip "ensure-wiki.py unit assertions" "python3 not available"
    return 0 2>/dev/null || true
fi

assert "ensure-wiki.py compiles" "python3 -m py_compile '$HOOK'"

run_hook() {  # repo-dir -> writes stdout to $2
    ( cd "$1" && printf '{}' | python3 "$HOOK" ) > "$2" 2>/dev/null
}

MYPROJ_OUT="$STAGE/myproj.out"
GITLAB_OUT="$STAGE/gitlab.out"
NEED_OUT="$STAGE/needclone.out"
run_hook "$STAGE/myproj"    "$MYPROJ_OUT"
run_hook "$STAGE/gitlab"    "$GITLAB_OUT"
run_hook "$STAGE/needclone" "$NEED_OUT"

# --- Identity (#7): the wiki name comes from origin, not the clone dir name ---
# myproj/ has the wiki at the CANONICAL path (wiki/canonical.wiki). A correct
# hook recognises it and prints nothing; a basename-deriving hook misses it,
# attempts a clone, and emits a nudge.
assert "identity: existing canonical wiki recognised -> hook stays silent" \
    "[ ! -s '$MYPROJ_OUT' ]"

# --- Scope (#5): non-GitHub origin is a silent no-op ---
assert "scope: non-GitHub origin -> no output" \
    "[ ! -s '$GITLAB_OUT' ]"

# --- Identity + output contract: clone-fail nudge names the CANONICAL path ---
assert "nudge names the canonical wiki path (wiki/canonical.wiki/)" \
    "grep -qF 'wiki/canonical.wiki/' '$NEED_OUT'"
assert "nudge does NOT name the clone-dir basename path (wiki/needclone.wiki/)" \
    "! grep -qF 'wiki/needclone.wiki/' '$NEED_OUT'"
assert "nudge is a valid SessionStart additionalContext object" \
    "python3 -c \"import json; h=json.load(open('$NEED_OUT'))['hookSpecificOutput']; assert h['hookEventName']=='SessionStart' and h['additionalContext']\""

# --- Clone mechanics (#1 partial-clone, #4 concurrency) ---
# Driven by a dedicated harness that exercises try_clone directly with real git.
assert "try_clone staging+rename: partial-clone & race safety" \
    "python3 '$HERE/tests/unit/ensure-wiki/clone_mechanics_test.py' '$HOOK'"

# --- Update mechanics (clean-FF, dirty gate, divergence, own-repo guard) ---
# Exercises update_wiki directly against real git (and jj when present).
assert "update_wiki fast-forward: clean-FF, dirty gate, divergence, guard" \
    "python3 '$HERE/tests/unit/ensure-wiki/update_mechanics_test.py' '$HOOK'"
