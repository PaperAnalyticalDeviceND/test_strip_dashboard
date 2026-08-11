#!/usr/bin/env bash
# Assertions: run the real init-wiki.sh in create mode against a fixture whose
# clone-dir basename differs from its origin repo name, verifying the
# shared-library wiring:
#   - namespace derived from origin (F1), not the directory basename;
#   - *.md.template files still resolved via the BASH_SOURCE anchor and
#     stamped (F10 regression guard);
#   - the printed push instruction names the detected branch, not 'master' (F5).
#
# Hermetic: git identity comes from sandbox_git_env; the wiki repo is pre-staged
# on 'trunk' by patch.sh so the F5 assertion can distinguish a detected branch
# from a hardcoded one. Create mode needs no network.

STAGE="$SANDBOX/init-wiki-naming"
# assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
REPO_ROOT_IW="$(cd "$HERE/../.." && pwd)"
INITWIKI="$REPO_ROOT_IW/wiki/init-wiki.sh"

assert "init-wiki.sh exists"         "[ -f '$INITWIKI' ]"
assert "init-wiki.sh passes bash -n" "bash -n '$INITWIKI'"

OUT="$( cd "$STAGE/clonedir" && bash "$INITWIKI" --agent test 2>&1 )"
RC=$?
# Fail loud if the run itself errored, so the file/branch checks below cannot
# pass for an unrelated setup reason.
assert "init-wiki create-mode run exits 0" "[ $RC -eq 0 ]"

# --- F1: namespace from origin (widget), not basename (clonedir) ---
assert "F1: wiki dir uses the origin name (widget.wiki)" \
    "[ -d '$STAGE/clonedir/wiki/widget.wiki' ]"
assert "F1: clone-dir basename NOT used (no clonedir.wiki)" \
    "[ ! -d '$STAGE/clonedir/wiki/clonedir.wiki' ]"
assert "F1: files namespaced with the origin name (SCHEMA_widget.md)" \
    "[ -f '$STAGE/clonedir/wiki/widget.wiki/SCHEMA_widget.md' ]"

# --- F10 regression: templates resolved via BASH_SOURCE anchor and stamped ---
assert "F10: *.md.template stamped into the wiki (Edge-Types.md)" \
    "[ -f '$STAGE/clonedir/wiki/widget.wiki/Edge-Types.md' ]"

# --- F5: printed push instruction names the detected branch, not master ---
PUSH_TRUNK=0;  case "$OUT" in *"push origin trunk"*)  PUSH_TRUNK=1 ;;  esac
PUSH_MASTER=0; case "$OUT" in *"push origin master"*) PUSH_MASTER=1 ;; esac
assert "F5: printed push uses the detected branch (trunk)" "[ $PUSH_TRUNK -eq 1 ]"
assert "F5: printed push does NOT hardcode master"         "[ $PUSH_MASTER -eq 0 ]"
