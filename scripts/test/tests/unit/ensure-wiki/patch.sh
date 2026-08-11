#!/usr/bin/env bash
# Patch: stage fixtures for the ensure-wiki.py hook unit test.
#
# Three git repos exercise the hook's identity + scope logic without touching
# the network for the success paths. A bogus "github.invalid" host is used for
# the clone-attempt paths so the clone fails fast (DNS) instead of reaching a
# real wiki; the 30s timeout caps it regardless.
#
#   myproj/    dir basename 'myproj', origin repo 'canonical', wiki ALREADY
#              present at the canonical path wiki/canonical.wiki/. A hook that
#              derives the wiki name from origin recognises it and stays silent;
#              one that uses the directory basename looks at wiki/myproj.wiki,
#              misses it, and tries to clone (emitting a nudge).
#   gitlab/    non-GitHub origin, no wiki -> GitHub-only scope means silent no-op.
#   needclone/ dir basename 'needclone', origin repo 'canonical', wiki ABSENT.
#              Clone is attempted and fails; the nudge must name the CANONICAL
#              path (wiki/canonical.wiki/), not the basename path.
set -uo pipefail

STAGE="$SANDBOX/ensure-wiki"
mkdir -p "$STAGE"

_mkrepo() {  # dir, origin-url
    git init -q "$1"
    git -C "$1" config user.email "ew-test@example.test"
    git -C "$1" config user.name  "ew test"
    git -C "$1" remote add origin "$2"
}

_mkrepo "$STAGE/myproj"    "https://github.invalid/owner/canonical.git"
mkdir -p "$STAGE/myproj/wiki/canonical.wiki"
: > "$STAGE/myproj/wiki/canonical.wiki/SCHEMA_canonical.md"

_mkrepo "$STAGE/gitlab"    "https://gitlab.com/owner/proj.git"

_mkrepo "$STAGE/needclone" "https://github.invalid/owner/canonical.git"

echo "  ensure-wiki unit patch staged at $STAGE"
