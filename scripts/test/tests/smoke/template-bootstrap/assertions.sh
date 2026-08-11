#!/usr/bin/env bash
# Smoke test assertions: template bootstrap.
# Verifies the template's own scripts pass syntax checks and produce the
# expected file structure after instantiate.sh runs.

T="$SANDBOX/template"

# If clone failed (no network, no MVP_TEMPLATE_LOCAL), skip everything.
if [ ! -d "$T" ]; then
    skip "template-bootstrap assertions" "template not cloned (offline + no MVP_TEMPLATE_LOCAL)"
    return 0 2>/dev/null || true
fi

# The exit status is asserted directly: every assertion below is
# presence-conditional and can pass against a half-bootstrapped tree
# (observed: a post-wiki instantiate death still reported 0 fail).
assert "instantiate.sh exited 0" \
    "[ \"\$(cat '$T.instantiate-rc' 2>/dev/null)\" = '0' ]"

# --- Syntax checks on the template's shipping scripts ---
# These are the bash -n checks template issue #5 explicitly calls for.
for script in \
    "$T/wiki/init-wiki.sh" \
    "$T/scripts/instantiate.sh" \
    "$T/scripts/update-from-template.sh" \
    "$T/scripts/check-template-version.sh"
do
    if [ -f "$script" ]; then
        assert "bash -n $(basename "$script") (syntax)" "bash -n '$script'"
    fi
done

# Agent-overlay setup scripts (if present)
for setup in "$T/wiki/agents"/*/setup.sh; do
    if [ -f "$setup" ]; then
        rel=$(echo "$setup" | sed "s|^$T/||")
        assert "bash -n $rel (syntax)" "bash -n '$setup'"
    fi
done

# --- instantiate.sh produced the expected baseline ---
# After instantiate "Smoke Test Project" --agent=claude-code, CLAUDE.md is
# NOT created (host-owned); the behavioral content ships as the tracked
# .claude/rules/*.md files, and README.md is rendered from its template.
assert "instantiate.sh did NOT create CLAUDE.md (host-owned now)" \
    "[ ! -f '$T/CLAUDE.md' ]"
if [ -f "$T/README.md" ]; then
    assert_contains "README.md has project name substituted (no {{PROJECT_NAME}} leak)" \
        "$T/README.md" "Smoke Test Project"
    assert "instantiate.sh did NOT leave {{PROJECT_NAME}} placeholder" \
        "! grep -q '{{PROJECT_NAME}}' '$T/README.md'"
fi

# The memory-boundary content ships as a rule file (kept overlay was
# claude-code, so .claude/rules/ survives instantiation).
RULEFILE="$T/.claude/rules/memory-boundary.md"
if [ -f "$RULEFILE" ]; then
    assert_contains "memory-boundary rule has the '# Memory boundary' heading" \
        "$RULEFILE" "# Memory boundary"
    assert_contains "memory-boundary rule names Claude-memory" \
        "$RULEFILE" "Claude-memory holds"
    assert_contains "memory-boundary rule names the wiki" \
        "$RULEFILE" "Wiki holds"
fi

# (The cursor overlay's parallel of this content is
# .cursor/rules/memory-boundary.mdc; instantiate --agent=claude-code prunes
# .cursor/, so it is not visible to this smoke test. The retired
# claude-md-snippet.md used to be asserted here.)

# --- Skills substituted at instantiate time ---
# instantiate.sh's glob (.claude/skills/wiki-*/SKILL.md) is the only
# substitution pass these files get; if the glob drifts from the layout it
# silently matches nothing and {{REPO_NAME}} leaks into every derived
# project. Positive + negative pair: the rendered wiki path can only appear
# if substitution actually ran, so a missing/renamed file cannot fake the
# negative check into a pass.
SKILL_LINT="$T/.claude/skills/wiki-lint/SKILL.md"
REPO_NAME_TB=$(basename "$T")
assert ".claude/skills/wiki-lint/SKILL.md present post-instantiate" \
    "[ -f '$SKILL_LINT' ]"
assert "SKILL.md substituted with the repo name (wiki/${REPO_NAME_TB}.wiki/)" \
    "grep -qF 'wiki/${REPO_NAME_TB}.wiki/' '$SKILL_LINT'"
assert "SKILL.md has no {{REPO_NAME}} leak" \
    "! grep -qF '{{REPO_NAME}}' '$SKILL_LINT'"

# --- init-wiki.sh produced the expected wiki structure ---
# init-wiki.sh is called by instantiate.sh and creates the wiki sub-repo
# with namespaced nav files.
REPO_NAME=$(basename "$T")
WIKI_SUB="$T/wiki/${REPO_NAME}.wiki"

assert "wiki sub-repo created at wiki/${REPO_NAME}.wiki/" \
    "[ -d '$WIKI_SUB/.git' ]"
# Namespaced nav files per init-wiki.sh's documented behavior
assert "Home_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/Home_${REPO_NAME}.md' ]"
assert "index_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/index_${REPO_NAME}.md' ]"
assert "log_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/log_${REPO_NAME}.md' ]"
assert "SCHEMA_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/SCHEMA_${REPO_NAME}.md' ]"
# Bridge file for GitHub wiki compatibility
assert "Home.md bridge exists at wiki root" \
    "[ -f '$WIKI_SUB/Home.md' ]"

# --- init-wiki.sh is idempotent: running it again should not error ---
# Per its docstring: "It is idempotent: safe to re-run on existing wikis
# (auto-detects create vs. update mode)."
if [ -f "$T/wiki/init-wiki.sh" ] && [ -d "$WIKI_SUB" ]; then
    RERUN_RC=$(cd "$T" && bash wiki/init-wiki.sh --name "Smoke Test Project" >/dev/null 2>&1; echo $?)
    assert_eq "init-wiki.sh is idempotent (re-runs cleanly on existing wiki)" "0" "$RERUN_RC"
fi

# --- Edge-Types.md.template was stamped into the wiki ---
# init-wiki.sh's *.md.template loop should produce wiki/<repo>.wiki/Edge-Types.md
# with placeholders substituted and the 16 forward-predicate anchored sections
# present so Variant 1 inline annotations resolve.
assert "Edge-Types.md present in the wiki" \
    "[ -f '$WIKI_SUB/Edge-Types.md' ]"

assert "Edge-Types.md has no placeholder leaks" \
    "! grep -qE '\{\{REPO_NAME\}\}|\{\{PROJECT_NAME\}\}' '$WIKI_SUB/Edge-Types.md'"

assert "Edge-Types.md up: resolves to SCHEMA_${REPO_NAME}" \
    "grep -qF 'up: \"[[SCHEMA_${REPO_NAME}]]\"' '$WIKI_SUB/Edge-Types.md'"

# All 16 anchored predicate sections (so Edge-Types#<pred> anchors resolve)
EDGE_PREDS="up source extends supports criticizes concept partOf dependsOn defines resolvedBy incorporatedInto outOfScopeFor precedes feedsInto related mentions"
ALL_PRESENT=1
for pred in $EDGE_PREDS; do
    if ! grep -qE "^## ${pred}$" "$WIKI_SUB/Edge-Types.md"; then
        ALL_PRESENT=0
        break
    fi
done
assert_eq "Edge-Types.md has all 16 forward-predicate anchored sections" "1" "$ALL_PRESENT"

# Generated SCHEMA contains the Variant 1 subsection that documents the form
assert "SCHEMA contains 'Inline body annotations (Variant 1)' subsection" \
    "grep -qF '## Inline body annotations (Variant 1)' '$WIKI_SUB/SCHEMA_${REPO_NAME}.md'"

# --- Home page navigation convention ---
# The Home_<repo>.md page is now seeded with a "## Categories" placeholder
# section, and the SCHEMA's Special Files block has a "### Home_<repo>.md"
# entry naming the category-level update rule. The Verification Gate has
# a matching criterion. The structural assertions below catch reversion
# of any of these claims.
HOME_PAGE="$WIKI_SUB/Home_${REPO_NAME}.md"
SCHEMA_FILE_HOME="$WIKI_SUB/SCHEMA_${REPO_NAME}.md"

# Seeded Home contains the Categories placeholder.
assert_contains "Home page has '## Categories' section" \
    "$HOME_PAGE" "## Categories"
assert_contains "Home page Categories section has the mirror-Index comment" \
    "$HOME_PAGE" "mirror their"
assert_contains "Home page Categories section has the empty-state placeholder" \
    "$HOME_PAGE" "No categories yet"

# Generated SCHEMA documents the Home Special-Files entry + the rule.
assert_contains "SCHEMA Special Files has 'Home_<repo>.md' entry" \
    "$SCHEMA_FILE_HOME" "Home_${REPO_NAME}"
assert_contains "SCHEMA Home entry states the category-level update rule" \
    "$SCHEMA_FILE_HOME" "Human-facing entry point"
assert_contains "SCHEMA Home entry mentions representative links convention" \
    "$SCHEMA_FILE_HOME" "representative links per category"

# Verification gate criterion present.
VGATE_HOME="$T/wiki/agents/verification-gate.md"
if [ -f "$VGATE_HOME" ]; then
    assert_contains "verification-gate.md has Home-page criterion" \
        "$VGATE_HOME" "reflects category-level changes"
fi

# Parallel-file-drift check: the new Home Special-Files entry's leading
# identifying line lives in two byte-identical copies in init-wiki.sh
# (create-mode heredoc + update-mode append_section_if_missing call).
INIT_WIKI_HOME="$T/wiki/init-wiki.sh"
if [ -f "$INIT_WIKI_HOME" ]; then
    HOME_ENTRY_COUNT=$(grep -c '^- Human-facing entry point\.' "$INIT_WIKI_HOME" || echo 0)
    assert_eq "init-wiki.sh Home Special-Files entry appears in exactly 2 places (parallel-pair byte-match)" \
        "2" "$HOME_ENTRY_COUNT"
fi

# --- Inverse edge vocabulary in SCHEMA (model_fusion rec #9(b)(i)) ---
# The Edges table now has an Inverse column listing the predicates the KG
# materialises. The accompanying prose says the agent does NOT assert
# inverses in source documents. The structural assertions below catch
# regression of any of these claims.
SCHEMA_FILE="$WIKI_SUB/SCHEMA_${REPO_NAME}.md"

assert_contains "SCHEMA Edges table has Inverse column header" \
    "$SCHEMA_FILE" "Edge \| Inverse \|"
assert_contains "SCHEMA Edges table lists extendedBy inverse" \
    "$SCHEMA_FILE" "extendedBy"
assert_contains "SCHEMA Edges table lists supportedBy inverse" \
    "$SCHEMA_FILE" "supportedBy"
assert_contains "SCHEMA Edges table lists criticizedBy inverse" \
    "$SCHEMA_FILE" "criticizedBy"
assert_contains "SCHEMA states inverses are KG-materialised, not authored" \
    "$SCHEMA_FILE" "Inverses are materialised by the KG"
assert_contains "SCHEMA states agents do NOT write inverse predicates in source documents" \
    "$SCHEMA_FILE" "Agents do not write"

# Edge-Types.md now declares the extendedBy inverse for extends (it was the
# only forward predicate missing an explicit inverse line in PR #16).
EDGE_TYPES="$WIKI_SUB/Edge-Types.md"
assert_contains "Edge-Types.md declares extendedBy as inverse of extends" \
    "$EDGE_TYPES" "Inverse: \`extendedBy\`"

# verification-gate.md aligns with the KG-materialises stance: the
# reciprocal-edge criterion now points the agent at body-level
# back-references and explicitly forbids asserting inverses in
# frontmatter. Catches a regression to the old (write-inverse-to-target)
# wording.
VGATE="$T/wiki/agents/verification-gate.md"
if [ -f "$VGATE" ]; then
    assert_contains "verification-gate.md references body-level back-references" \
        "$VGATE" "body-level back-reference"
    assert_contains "verification-gate.md says agents do NOT assert inverse predicates" \
        "$VGATE" "agents do not assert inverse predicates"
fi

# Parallel-file-drift check: the new Edges table line appears in two
# byte-identical copies in init-wiki.sh (create-mode heredoc +
# update-mode append_section_if_missing call). Either copy drifting from
# the other means derived projects land in inconsistent states.
INIT_WIKI="$T/wiki/init-wiki.sh"
if [ -f "$INIT_WIKI" ]; then
    EDGE_HEADER_COUNT=$(grep -c '^| Edge | Inverse | What it licenses the agent to do |$' "$INIT_WIKI" || echo 0)
    assert_eq "init-wiki.sh Edges-table header appears in exactly 2 places (parallel-pair byte-match)" \
        "2" "$EDGE_HEADER_COUNT"
fi

# --- SessionStart hook auto-loads wiki state (model_fusion rec #1) ---
# The hook template ships content-injection logic so the wiki functions
# as compounding memory rather than RAG-on-demand. Structural assertions
# below catch the case where the template gets reverted to the
# orientation-only form. The behavioral end-to-end test (rendered hook
# against a stub wiki, last-5-of-7 log-entry selection, no-wiki
# graceful skip) lives in the integration/session-start-hook stage.
SS_HOOK_TPL="$T/wiki/agents/claude-code/templates/session-start-hook.sh"
if [ -f "$SS_HOOK_TPL" ]; then
    # assert_contains uses grep -qE; ${REPO_NAME} would be regex-interpreted
    # ($ is end-of-line, {} are metacharacters). For the index-path check we
    # use a regex-safe substring that is unique within the template.
    assert_contains "session-start-hook template references the wiki index" \
        "$SS_HOOK_TPL" 'INDEX_FILE="wiki/'
    assert_contains "session-start-hook template injects the index header" \
        "$SS_HOOK_TPL" "Wiki current state — index"
    assert_contains "session-start-hook template emits last-5 log entries header" \
        "$SS_HOOK_TPL" "last 5 log entries"
    assert_contains "session-start-hook template uses awk to slice log entries" \
        "$SS_HOOK_TPL" "awk"
fi

# --- analysis + decision page types ---
# init-wiki.sh now declares both in the SCHEMA frontmatter type list and
# adds a "## Page types" subsection that defines their required structure.
# The list lives in two byte-identical copies in init-wiki.sh (create-mode
# heredoc + update-mode append_section_if_missing call); the structural
# assertions below confirm the generated SCHEMA has them, and the
# duplicate-line check confirms init-wiki.sh's two copies still match.

SCHEMA_FILE="$WIKI_SUB/SCHEMA_${REPO_NAME}.md"

# Type list contains analysis and decision
assert_contains "SCHEMA type list contains 'analysis'" \
    "$SCHEMA_FILE" "analysis"
assert_contains "SCHEMA type list contains 'decision'" \
    "$SCHEMA_FILE" "decision"

# Page types subsection is present, with both type definitions
assert_contains "SCHEMA contains '## Page types' subsection" \
    "$SCHEMA_FILE" "## Page types"
assert_contains "SCHEMA Page types defines 'analysis' subsection" \
    "$SCHEMA_FILE" "### \`analysis\`"
assert_contains "SCHEMA Page types defines 'decision' subsection" \
    "$SCHEMA_FILE" "### \`decision\`"
assert_contains "SCHEMA analysis pages require derived_from frontmatter" \
    "$SCHEMA_FILE" "derived_from:"
assert_contains "SCHEMA decision pages require decided_at frontmatter" \
    "$SCHEMA_FILE" "decided_at:"

# Verification gate references the new page-type requirements
VGATE="$T/wiki/agents/verification-gate.md"
if [ -f "$VGATE" ]; then
    assert_contains "verification-gate.md mentions analysis page requirements" \
        "$VGATE" "type: analysis"
    assert_contains "verification-gate.md mentions decision page requirements" \
        "$VGATE" "type: decision"
fi

# Parallel-file-drift check: the type-list line lives in two places in
# init-wiki.sh (the create-mode heredoc and the update-mode append call).
# They must be byte-identical for derived projects to land in the same
# state regardless of which path their wiki took.
INIT_WIKI="$T/wiki/init-wiki.sh"
if [ -f "$INIT_WIKI" ]; then
    TYPE_LIST_COUNT=$(grep -c "^type: concept | entity | source-summary | synthesis | analysis | decision | index | comparison | untyped$" "$INIT_WIKI" || echo 0)
    assert_eq "init-wiki.sh type list appears in exactly 2 places (parallel-pair byte-match)" \
        "2" "$TYPE_LIST_COUNT"
fi

# --- wiki-write-protocol rename (PR6) ---
# scripts/multi-agent-write-protocol-proto/ was renamed to
# scripts/wiki-write-protocol/. These assertions lock the new path in
# and catch any regression that restores the old name.
assert "scripts/wiki-write-protocol/ directory exists at the renamed path" \
    "[ -d '$T/scripts/wiki-write-protocol' ]"
assert "scripts/multi-agent-write-protocol-proto/ no longer exists at the old path" \
    "[ ! -d '$T/scripts/multi-agent-write-protocol-proto' ]"
assert "wiki-write-protocol README references the new directory name in its layout" \
    "grep -qF 'scripts/wiki-write-protocol/' '$T/scripts/wiki-write-protocol/README.md'"

# --- wiki-write-protocol wiring (PR7) ---
# Three behavioural checks that catch real regressions in the wiring:
# (1) the agent-agnostic procedure doc ships in the template (otherwise
#     the references on skill/rules/command files dangle silently —
#     no other test fails);
# (2) the per-overlay skill files reference the procedure doc (otherwise
#     the wiring decays invisibly: the doc exists but no agent reads it);
# (3) the manifest's TEMPLATE_SHARED_INFRA lists the procedure doc +
#     protocol.sh (otherwise derived projects never receive PR7's payload).
WWP_DOC="$T/wiki/agents/wiki-write-protocol.md"
assert "wiki-write-protocol.md ships in the template repo" \
    "[ -f '$WWP_DOC' ]"

# Unconditional (no [ -f ] guard): a renamed or misplaced skill directory
# must fail here, not silently skip the reference check.
for skill in wiki-experiment wiki-source wiki-lint; do
    skill_path="$T/.claude/skills/${skill}/SKILL.md"
    assert ".claude/skills/${skill}/SKILL.md ships in the template repo" \
        "[ -f '$skill_path' ]"
    assert_contains ".claude/skills/${skill}/SKILL.md references wiki-write-protocol.md" \
        "$skill_path" "wiki-write-protocol.md"
done

# scripts/lib/template-manifest.sh is the single source of truth that the
# sync scripts consume. A path listed there reaches derived projects via
# update-from-template AND is checked by check-template-version. Replaces
# the parallel-pair byte-match assertions: by-construction guarantee from
# a shared manifest is stronger than a count-agnostic grep on each script.
MANIFEST="$T/scripts/lib/template-manifest.sh"
if [ -f "$MANIFEST" ]; then
    assert "manifest TEMPLATE_SHARED_INFRA lists wiki-write-protocol.md" \
        "grep -qF 'wiki/agents/wiki-write-protocol.md' '$MANIFEST'"
    assert "manifest TEMPLATE_SHARED_INFRA lists wiki-write-protocol/protocol.sh" \
        "grep -qF 'scripts/wiki-write-protocol/protocol.sh' '$MANIFEST'"
fi
