#!/usr/bin/env bash
# Assertions: syntactic + arg-handling sanity for the agent-comms feature's
# payload scripts. Layer 2 from Comms-Feature-Design: fast, no network,
# no auth, no real LLM. Catches the kind of regression where someone
# introduces a syntax error or breaks arg parsing / exit codes.
#
# Direct mode is exercised against a local fixture index (no network)
# with bogus wiki_clone_url so the clone step fails-but-the-script
# survives. Confirms resolution + per-agent failure isolation.

REPO_ROOT_ACSS="$(cd "$HERE/../.." && pwd)"
CODE_DIR="$REPO_ROOT_ACSS/features/agent-comms/code"
ASK="$CODE_DIR/ask.sh"
ENROLL="$CODE_DIR/enroll.sh"

# Locate the fixture-index.json next to this assertions.sh file.
TEST_DIR_ACSS="$REPO_ROOT_ACSS/scripts/test/tests/unit/agent-comms-script-shape"
FIXTURE_INDEX="$TEST_DIR_ACSS/fixture-index.json"
FIXTURE_URL="file://$FIXTURE_INDEX"

# Per-call sandbox for $LLM_AGENTS_DIR so the test never writes to the
# user's real ~/.llm-agents/. Each ask.sh invocation gets its own dir
# (cheap; tests are short and isolated).
LLM_AGENTS_SANDBOX="${SANDBOX}/agent-comms-script-shape-llm-agents"
mkdir -p "$LLM_AGENTS_SANDBOX"

# --- Bash syntax + executability ---
assert "ask.sh exists"             "[ -f '$ASK' ]"
assert "ask.sh is executable"      "[ -x '$ASK' ]"
assert "ask.sh passes bash -n"     "bash -n '$ASK'"

assert "enroll.sh exists"          "[ -f '$ENROLL' ]"
assert "enroll.sh is executable"   "[ -x '$ENROLL' ]"
assert "enroll.sh passes bash -n"  "bash -n '$ENROLL'"

# --- Fixture sanity ---
assert "fixture-index.json exists"  "[ -f '$FIXTURE_INDEX' ]"
assert "fixture-index.json is valid JSON" \
       "jq empty '$FIXTURE_INDEX'"

# --- ask.sh: no-args / wrong-args ---
NOARGS_ERR=$(mktemp); NOARGS_RC=0
bash "$ASK" </dev/null >/dev/null 2>"$NOARGS_ERR" || NOARGS_RC=$?
assert "ask.sh with no args exits non-zero"          "[ '$NOARGS_RC' -ne 0 ]"
assert "ask.sh with no args prints Usage on stderr"  "grep -qF 'Usage:' '$NOARGS_ERR'"

# Empty-string question, 1-arg form
EMPTY1_RC=0
bash "$ASK" "" >/dev/null 2>/dev/null || EMPTY1_RC=$?
assert "ask.sh \"\" (1-arg) exits with code 5"        "[ '$EMPTY1_RC' -eq 5 ]"

# Empty-string question, 2-arg form (direct mode)
EMPTY2_RC=0
bash "$ASK" agent "" >/dev/null 2>/dev/null || EMPTY2_RC=$?
assert "ask.sh <agent> \"\" (2-arg) exits with code 5" "[ '$EMPTY2_RC' -eq 5 ]"

# --- ask.sh: --help / -h ---
HELP_OUT=$(mktemp); HELP_RC=0
bash "$ASK" --help >"$HELP_OUT" 2>/dev/null || HELP_RC=$?
assert "ask.sh --help exits 0"                  "[ '$HELP_RC' -eq 0 ]"
assert "ask.sh --help prints Usage to stdout"   "grep -qF 'Usage:' '$HELP_OUT'"
assert "ask.sh --help mentions direct mode"     "grep -qF 'direct mode' '$HELP_OUT'"

H_RC=0; bash "$ASK" -h >/dev/null 2>&1 || H_RC=$?
assert "ask.sh -h exits 0"                       "[ '$H_RC' -eq 0 ]"

# --- ask.sh: too many args ---
TOOMANY_RC=0
bash "$ASK" a b c >/dev/null 2>/dev/null || TOOMANY_RC=$?
assert "ask.sh with 3 args exits non-zero"       "[ '$TOOMANY_RC' -ne 0 ]"

# --- ask.sh: direct mode resolution against fixture ---
# Unknown agent -> exit 7 with "not found"
UNK_ERR=$(mktemp); UNK_RC=0
FEDERATION_INDEX_URL="$FIXTURE_URL" LLM_AGENTS_DIR="$LLM_AGENTS_SANDBOX" \
  bash "$ASK" nonexistent-agent "irrelevant" >/dev/null 2>"$UNK_ERR" || UNK_RC=$?
assert "direct mode: unknown agent exits 7"                         "[ '$UNK_RC' -eq 7 ]"
assert "direct mode: unknown agent prints 'not found' on stderr"    "grep -qF 'not found' '$UNK_ERR'"
assert "direct mode: unknown agent lists available agents"          "grep -qF 'fixtureuser/fixture-agent' '$UNK_ERR'"

# Exact-id match -> resolution succeeds (clone will fail since URL is bogus,
# but that's a SKIP, not a fatal). Exit 0 (per-agent failures isolated).
EXACT_OUT=$(mktemp); EXACT_ERR=$(mktemp); EXACT_RC=0
FEDERATION_INDEX_URL="$FIXTURE_URL" LLM_AGENTS_DIR="$LLM_AGENTS_SANDBOX" \
  bash "$ASK" fixtureuser/fixture-agent "irrelevant" >"$EXACT_OUT" 2>"$EXACT_ERR" || EXACT_RC=$?
assert "direct mode: exact-id resolution exits 0"                   "[ '$EXACT_RC' -eq 0 ]"
assert "direct mode: exact-id prints attribution header to stdout"  "grep -qF '=== fixtureuser/fixture-agent ===' '$EXACT_OUT'"
assert "direct mode: bogus clone url surfaces SKIP on stderr"       "grep -qF 'SKIP: clone failed' '$EXACT_ERR'"

# Exact owner_repo match
OR_OUT=$(mktemp); OR_RC=0
FEDERATION_INDEX_URL="$FIXTURE_URL" LLM_AGENTS_DIR="$LLM_AGENTS_SANDBOX" \
  bash "$ASK" fixture-org/fixture-agent "irrelevant" >"$OR_OUT" 2>/dev/null || OR_RC=$?
assert "direct mode: exact owner_repo resolution exits 0"           "[ '$OR_RC' -eq 0 ]"
assert "direct mode: owner_repo match prints correct id header"     "grep -qF '=== fixtureuser/fixture-agent ===' '$OR_OUT'"

# Repo basename match (single basename, unambiguous)
BN_OUT=$(mktemp); BN_RC=0
FEDERATION_INDEX_URL="$FIXTURE_URL" LLM_AGENTS_DIR="$LLM_AGENTS_SANDBOX" \
  bash "$ASK" fixture-agent "irrelevant" >"$BN_OUT" 2>/dev/null || BN_RC=$?
assert "direct mode: basename resolution exits 0"                   "[ '$BN_RC' -eq 0 ]"
assert "direct mode: basename match prints correct id header"       "grep -qF '=== fixtureuser/fixture-agent ===' '$BN_OUT'"

# --- enroll.sh: --help / -h ---
ENROLL_HELP=$(mktemp); ENROLL_HELP_RC=0
bash "$ENROLL" --help >"$ENROLL_HELP" 2>/dev/null || ENROLL_HELP_RC=$?
assert "enroll.sh --help exits 0"                          "[ '$ENROLL_HELP_RC' -eq 0 ]"
assert "enroll.sh --help prints Usage to stdout"           "grep -qF 'Usage:' '$ENROLL_HELP'"
assert "enroll.sh --help mentions --dry-run"               "grep -qF -- '--dry-run' '$ENROLL_HELP'"

# --- enroll.sh: unknown flag ---
ENROLL_UNK_ERR=$(mktemp); ENROLL_UNK_RC=0
bash "$ENROLL" --bogus-flag </dev/null >/dev/null 2>"$ENROLL_UNK_ERR" || ENROLL_UNK_RC=$?
assert "enroll.sh unknown flag exits 2"                    "[ '$ENROLL_UNK_RC' -eq 2 ]"
assert "enroll.sh unknown flag prints 'unknown flag'"      "grep -qF 'unknown flag' '$ENROLL_UNK_ERR'"

# --- enroll.sh: outside a git repo ---
NOGIT_DIR="$SANDBOX/agent-comms-enroll-nogit"
mkdir -p "$NOGIT_DIR"
ENROLL_NOGIT_ERR=$(mktemp); ENROLL_NOGIT_RC=0
( cd "$NOGIT_DIR" && bash "$ENROLL" </dev/null >/dev/null 2>"$ENROLL_NOGIT_ERR" ) || ENROLL_NOGIT_RC=$?
assert "enroll.sh outside git repo exits 12"               "[ '$ENROLL_NOGIT_RC' -eq 12 ]"
assert "enroll.sh outside git repo prints 'not in a git'"  "grep -qF 'not in a git repository' '$ENROLL_NOGIT_ERR'"

# --- enroll.sh: inside git repo but no wiki/ ---
INREPO_DIR="$SANDBOX/agent-comms-enroll-no-wiki"
mkdir -p "$INREPO_DIR"
git -C "$INREPO_DIR" init -q 2>/dev/null
ENROLL_NOWIKI_ERR=$(mktemp); ENROLL_NOWIKI_RC=0
( cd "$INREPO_DIR" && bash "$ENROLL" </dev/null >/dev/null 2>"$ENROLL_NOWIKI_ERR" ) || ENROLL_NOWIKI_RC=$?
assert "enroll.sh no wiki dir exits 9"                     "[ '$ENROLL_NOWIKI_RC' -eq 9 ]"
assert "enroll.sh no wiki dir prints 'wiki sub-repo not found'" \
       "grep -qF 'wiki sub-repo not found' '$ENROLL_NOWIKI_ERR'"
assert "enroll.sh no wiki dir suggests init-wiki.sh"       "grep -qF 'init-wiki.sh' '$ENROLL_NOWIKI_ERR'"

# --- Cleanup temp files ---
rm -f "$NOARGS_ERR" "$HELP_OUT" "$UNK_ERR" "$EXACT_OUT" "$EXACT_ERR" "$OR_OUT" "$BN_OUT" \
      "$ENROLL_HELP" "$ENROLL_UNK_ERR" "$ENROLL_NOGIT_ERR" "$ENROLL_NOWIKI_ERR"
rm -rf "$NOGIT_DIR" "$INREPO_DIR"
