#!/usr/bin/env bash
# Assertions: instantiate.sh strips the template-development-only
# .claude/rules/ from a derived project, while keeping the rest of .claude/.
#
# The contrast that proves the strip: the dev-only rule ships in the template
# (precondition) and .claude/ + .claude/skills/ survive the claude-code
# overlay, but the dev-only rule is gone afterwards while a sibling
# consumer-facing rule is left untouched. Neutralizing the strip flips the
# "stripped" assertion red; regressing to a whole-directory rm -rf flips the
# "sibling survives" assertion red.

T="$SANDBOX/template-dev-rules"

if [ ! -d "$T" ]; then
    skip "instantiate-strips-dev-rules assertions" "template not cloned (offline + no MVP_TEMPLATE_LOCAL)"
    return 0 2>/dev/null || true
fi

# Exit status first: the assertions below are presence-conditional and can
# pass against a half-bootstrapped tree (mid-run deaths were WARN-swallowed).
assert "instantiate.sh exited 0" \
    "[ \"\$(cat '$T.instantiate-rc' 2>/dev/null)\" = '0' ]"

# Precondition: the template shipped .claude/rules/ before instantiation.
# Without this, "stripped after" would hold trivially against a tree that
# never had the directory.
assert "template shipped .claude/rules/ before instantiation" \
    "[ -f '$SANDBOX/dev-rules-was-present' ]"

# --agent=claude-code KEEPS .claude/ (commands/skills). If these fail, the
# run never reached the overlay step and the strip assertion below would be
# vacuous, so they guard against that.
assert "instantiate kept .claude/ (claude-code overlay)" \
    "[ -d '$T/.claude' ]"
assert "instantiate kept .claude/skills/ (overlay content intact)" \
    "[ -f '$T/.claude/skills/wiki-lint/SKILL.md' ]"

# Behaviour under test: the named dev-only rules did not propagate.
assert "instantiate stripped the dev-only observe-the-failure rule" \
    "[ ! -f '$T/.claude/rules/observe-the-failure.md' ]"
assert "template shipped the local-testing rule before instantiation" \
    "[ -f '$SANDBOX/local-testing-rule-was-present' ]"
assert "instantiate stripped the dev-only local-testing rule" \
    "[ ! -f '$T/.claude/rules/local-testing.md' ]"

# ...but only that one: a consumer-facing rule (and the directory) survive.
# This is what makes the strip file-scoped rather than rm -rf.
assert "a consumer-facing rule under .claude/rules/ survives" \
    "[ -f '$T/.claude/rules/keep-me.md' ]"
assert "the .claude/rules/ directory is kept when a rule remains" \
    "[ -d '$T/.claude/rules' ]"
