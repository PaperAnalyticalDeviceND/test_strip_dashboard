#!/usr/bin/env bash
# Patch: fixtures for the template sync scripts (update-from-template.sh,
# check-template-version.sh) migrated onto the shared library (chunk 04).
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.
# Effects: creates $SANDBOX/template-scripts/ with:
#   template-main/   a stand-in template repo, default branch 'main', holding
#                    one substituted file (.claude/skills/wiki-experiment/SKILL.md
#                    with a literal {{REPO_NAME}})
#   template-trunk/  same content, default branch 'trunk' (NOT main), so the
#                    scripts must DETECT the branch rather than assume main (F5)
#   wrong-remote/    an unrelated repo, used to trip the remote guard (F6)
#   up-clone/        project whose basename differs from its wiki name (widget);
#                    run update against template-main (F1/F2 substitution, F12)
#   br-clone/        project pointed at template-trunk (F5)
#   gd-clone/        project with a pre-existing 'template' remote -> wrong-remote
#                    (F6 guard)
#   ck-clone/        project whose wiki is 'gizmo'; run check-template-version
#                    (F1/F2 name discovery in the second script)
#
# Hermetic: all "remotes" are local paths, contacted over the local transport.

set -uo pipefail

STAGE="$SANDBOX/template-scripts"
mkdir -p "$STAGE"

# Thin alias; identity/default-branch come from the harness-wide hermetic git
# env (sandbox_git_env), so the helpers below read cleanly. Branches that an
# assertion checks are set explicitly via symbolic-ref, since init.defaultBranch
# is honoured only on git >=2.28.
g() { git "$@"; }

# Seed a template-content repo at $1 on branch $2 with the one file the sync
# scripts will substitute.
_mk_template() {
    local dir="$1" branch="$2"
    g init -q "$dir"
    g -C "$dir" symbolic-ref HEAD "refs/heads/$branch"
    mkdir -p "$dir/.claude/skills/wiki-experiment"
    printf 'command for {{REPO_NAME}}\n' > "$dir/.claude/skills/wiki-experiment/SKILL.md"
    g -C "$dir" add -A
    g -C "$dir" commit -q -m "template content on $branch"
}

# A project fixture: git repo at $1, with an on-disk wiki named $2 and an
# active .claude/ overlay (so TEMPLATE_OVERLAY_CLAUDE is in the sync list), plus a
# stale local copy of the substituted file.
_mk_project() {
    local dir="$1" wiki="$2"
    g init -q "$dir"
    mkdir -p "$dir/wiki/$wiki.wiki"
    : > "$dir/wiki/$wiki.wiki/SCHEMA_$wiki.md"
    mkdir -p "$dir/.claude/skills/wiki-experiment"
    printf 'stale local content\n' > "$dir/.claude/skills/wiki-experiment/SKILL.md"
}

_mk_template "$STAGE/template-main"  main
_mk_template "$STAGE/template-trunk" trunk

# wrong-remote: unrelated repo for the guard test.
g init -q "$STAGE/wrong-remote"
printf 'unrelated\n' > "$STAGE/wrong-remote/README.md"
g -C "$STAGE/wrong-remote" add -A
g -C "$STAGE/wrong-remote" commit -q -m "unrelated repo"

_mk_project "$STAGE/up-clone" widget
_mk_project "$STAGE/br-clone" widget
_mk_project "$STAGE/gd-clone" widget
_mk_project "$STAGE/ck-clone" gizmo

# gd-clone already has a 'template' remote pointing at the WRONG repo; the
# guard must reject it rather than fetch (F6).
g -C "$STAGE/gd-clone" remote add template "$STAGE/wrong-remote"

echo "  template-scripts patch applied: fixtures at $STAGE"
