#!/usr/bin/env bash
# Patch: stage a fixture for the init-wiki naming / push-branch test.
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.
# Effects: creates $SANDBOX/init-wiki-naming/ with:
#   clonedir/  git repo whose basename ('clonedir') deliberately differs from
#              its origin repo name ('widget'), proving init-wiki derives the
#              namespace from origin, not the clone directory (F1).
#
# Hermetic: create mode needs no network (init-wiki inits the wiki locally).

set -uo pipefail

STAGE="$SANDBOX/init-wiki-naming"
mkdir -p "$STAGE"

git init -q "$STAGE/clonedir"
git -C "$STAGE/clonedir" remote add origin "https://github.com/acme/widget.git"

# Pre-create the wiki repo on a non-master branch portably. init-wiki.sh only
# runs its own `git init` when .git is absent, so it inherits this HEAD and
# detects 'trunk' independent of git version. `git init -b`/init.defaultBranch
# both need git >=2.28; symbolic-ref works back to git 2.7. The F5 assertion
# then tells a detected branch apart from a hardcoded 'master'.
WIKIREPO="$STAGE/clonedir/wiki/widget.wiki"
mkdir -p "$WIKIREPO"
git init -q "$WIKIREPO"
git -C "$WIKIREPO" symbolic-ref HEAD refs/heads/trunk

echo "  init-wiki-naming patch applied: fixture at $STAGE"
