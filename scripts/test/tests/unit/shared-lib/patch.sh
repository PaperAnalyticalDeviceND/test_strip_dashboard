#!/usr/bin/env bash
# Patch: build the git + wiki fixtures the shared-lib assertions run against.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/shared-lib/ containing:
#   repo-https/    git repo, origin = HTTPS .git URL
#   repo-ssh/      git repo, origin = scp-style SSH URL
#   repo-noorigin/ git repo with no origin remote
#   notrepo/       a plain directory (not a git repo)
#   wiki-one/      project with exactly one wiki/<name>.wiki
#   wiki-none/     project with wiki/ but no *.wiki
#   wiki-many/     project with two wiki/*.wiki dirs
#   branch/clone/  clone of a bare remote whose default branch is 'trunk'
#                  (so lw_default_branch must DETECT it, not assume main/master)

set -uo pipefail

ROOT="$SANDBOX/shared-lib"
mkdir -p "$ROOT"

# Init a repo with a deterministic identity so commits work even where the
# global git identity is unset (CI).
_mkrepo() {
    git init -q "$1"
    git -C "$1" config user.email "lib-test@example.test"
    git -C "$1" config user.name  "lib test"
}

# --- origin URL fixtures (no network: remotes are never contacted) ---
_mkrepo "$ROOT/repo-https"
git -C "$ROOT/repo-https" remote add origin "https://github.com/acme/widget.git"

_mkrepo "$ROOT/repo-ssh"
git -C "$ROOT/repo-ssh" remote add origin "git@github.com:acme/widget.git"

_mkrepo "$ROOT/repo-noorigin"

# --- not a git repo ---
mkdir -p "$ROOT/notrepo"

# --- wiki discovery fixtures ---
mkdir -p "$ROOT/wiki-one/wiki/my-proj.wiki"
: > "$ROOT/wiki-one/wiki/my-proj.wiki/SCHEMA_my-proj.md"
mkdir -p "$ROOT/wiki-none/wiki"
mkdir -p "$ROOT/wiki-many/wiki/a.wiki" "$ROOT/wiki-many/wiki/b.wiki"

# --- branch-detection fixture: bare remote whose default branch is 'trunk' ---
# symbolic-ref is the version-portable way to set a bare repo's default
# branch (matches scripts/wiki-write-protocol/sandbox.sh; `git init -b` is
# newer). Seed a commit on trunk, push it, then clone so the clone's
# refs/remotes/origin/HEAD symref resolves to origin/trunk.
BD="$ROOT/branch"
mkdir -p "$BD"
git init --bare -q "$BD/remote.git"
git -C "$BD/remote.git" symbolic-ref HEAD refs/heads/trunk
_mkrepo "$BD/seed"
git -C "$BD/seed" symbolic-ref HEAD refs/heads/trunk
git -C "$BD/seed" commit --allow-empty -q -m "seed"
git -C "$BD/seed" remote add origin "$BD/remote.git"
git -C "$BD/seed" push -q origin trunk
git clone -q "$BD/remote.git" "$BD/clone"

# --- lw_ensure_remote fixtures (git.sh) ---
# 'none' has no template remote (add path); 'has' already points at a repo, so
# the same repo in another URL form is accepted and a different repo rejected.
_mkrepo "$ROOT/ensure/none"
_mkrepo "$ROOT/ensure/has"
git -C "$ROOT/ensure/has" remote add template "https://github.com/acme/widget.git"

# --- sha256 fixtures (sys.sh: lw_sha256) ---
# A fixed-content input whose digest is known, plus a fake PATH dir that
# provides shasum + awk but NOT sha256sum, so the fallback branch can be
# exercised deterministically. The shims are symlinks to the real tools; if
# shasum is unavailable on this host the assertion skips.
SHA="$ROOT/sha"
mkdir -p "$SHA"
printf 'llm-wiki\n' > "$SHA/input.txt"
FAKEBIN="$ROOT/sha-fakebin"
mkdir -p "$FAKEBIN"
if command -v shasum >/dev/null 2>&1 && command -v awk >/dev/null 2>&1; then
    ln -sf "$(command -v shasum)" "$FAKEBIN/shasum"
    ln -sf "$(command -v awk)"    "$FAKEBIN/awk"
fi

echo "  shared-lib patch applied: fixtures at $ROOT"
