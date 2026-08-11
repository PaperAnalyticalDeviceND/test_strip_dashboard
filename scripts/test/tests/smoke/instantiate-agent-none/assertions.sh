#!/usr/bin/env bash
# Assertions for the --agent=none regression smoke test (issue #9).
#
# Before the fix, instantiate.sh exited non-zero with
#   "INIT_AGENT_ARGS[@]: unbound variable"
# on bash 3.2 and init-wiki.sh never ran. After the fix, the script
# completes and produces the rendered README + the wiki sub-repo.

T="$SANDBOX/template-none"

if [ ! -d "$T" ]; then
    skip "instantiate-agent-none assertions" "template not cloned (offline + no MVP_TEMPLATE_LOCAL)"
    return 0 2>/dev/null || true
fi

# Exit status first: the assertions below are presence-conditional and can
# pass against a half-bootstrapped tree (mid-run deaths were WARN-swallowed).
assert "instantiate.sh --agent=none exited 0" \
    "[ \"\$(cat '$T.instantiate-rc' 2>/dev/null)\" = '0' ]"

# Bootstrap exit + README substitution (CLAUDE.md is host-owned and no
# longer rendered by instantiate)
assert "instantiate.sh --agent=none did NOT create CLAUDE.md" \
    "[ ! -f '$T/CLAUDE.md' ]"
assert_contains "README.md has project name substituted" \
    "$T/README.md" "Agent None Project"
assert "README.md has no {{PROJECT_NAME}} leak" \
    "! grep -q '{{PROJECT_NAME}}' '$T/README.md'"

# init-wiki.sh must have run (the regression killed it before it could fire)
REPO_NAME=$(basename "$T")
WIKI_SUB="$T/wiki/${REPO_NAME}.wiki"

assert "wiki sub-repo created at wiki/${REPO_NAME}.wiki/ (init-wiki.sh ran)" \
    "[ -d '$WIKI_SUB/.git' ]"
assert "Home_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/Home_${REPO_NAME}.md' ]"
assert "SCHEMA_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/SCHEMA_${REPO_NAME}.md' ]"

# --agent=none means no agent-overlay files should have been copied into
# the project root. The template ships agent overlays under wiki/agents/
# but instantiate.sh should NOT have created .claude/ or .cursor/ when
# --agent=none.
assert "no .claude/ overlay copied when --agent=none" \
    "[ ! -d '$T/.claude' ]"
assert "no .cursor/ overlay copied when --agent=none" \
    "[ ! -d '$T/.cursor' ]"
