#!/usr/bin/env bash
# Patch: stage a template copy and a virgin host, then adopt into the host.
#
# The assertions prove the ADOPTED HOST's own sync tooling works — the
# tooling adopt itself installs (#74: update-from-template.sh and
# check-template-version.sh source scripts/lib/template-manifest.sh from
# the HOST tree, so adopt must ship the manifest too) — and that the
# host's wiki carries the stamped Edge-Types page (#75: init-wiki stamps
# wiki/*.md.template from the HOST's wiki/ under nullglob, so a template
# file adopt never shipped is a silent no-op).
#
# The template side is staged via clone_template into the sandbox (a real
# git repo with one commit on a detectable default branch) rather than
# pointing at this checkout directly: CI checkouts are detached-HEAD and
# PR runs may lack a local main, which would break the host-side
# `git fetch template <branch>` for reasons unrelated to #74.
#
# Inputs:  SANDBOX env var. lib/template.sh's clone_template.
# Effects: $SANDBOX/adopted-host-sync/{template,host}; host adopted with
#          --agent=claude-code. Declines cleanly (nothing staged) when no
#          template source is available (offline, or derived checkout per
#          issue #15).
#
# Idempotent.

set -uo pipefail

HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

STAGE="$SANDBOX/adopted-host-sync"
T="$STAGE/template"
H="$STAGE/host"
mkdir -p "$STAGE"

if [ -d "$T" ]; then
    echo "  adopted-host-sync template already staged at $T (idempotent re-run)."
elif ! clone_template "$T"; then
    echo "  adopted-host-sync assertions will skip: no template clone available." >&2
    rm -rf "$STAGE"
    exit 0
fi

if [ ! -d "$H/.git" ]; then
    git init -q "$H"
    git -C "$H" remote add origin "https://github.com/acme/sync-host.git"
    echo "# Sync Host" > "$H/README.md"
    git -C "$H" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H" -c user.email=t@x.invalid -c user.name=t commit -qm "initial"
fi

if [ ! -f "$H/llm-wiki.md" ]; then
    rc=0
    bash "$T/scripts/adopt.sh" --target="$H" --apply --agent=claude-code \
        >/tmp/adopted-host-sync.log 2>&1 || rc=$?
    # rc sidecar outside the tree; assertions.sh asserts rc == 0.
    echo "$rc" > "$H.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed (rc=$rc); the exit-status assertion will fail." >&2
        sed 's/^/    /' /tmp/adopted-host-sync.log >&2
    fi
fi

# --- H2: manifest-less host with the CURRENT updater (#74 bootstrap path) ---
# Covers the new updater's self-heal branch: manifest missing, updater
# recent enough to bootstrap it from the template ref. NOTE this is NOT
# the genuine pre-fix combination — a real legacy host has the OLD
# updater, which dies before any fetch; that case is H4 below.
H2="$STAGE/legacy-host"
if [ ! -d "$H2/.git" ]; then
    git init -q "$H2"
    git -C "$H2" remote add origin "https://github.com/acme/legacy-host.git"
    echo "# Legacy Host" > "$H2/README.md"
    git -C "$H2" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H2" -c user.email=t@x.invalid -c user.name=t commit -qm "initial"
    rc=0
    bash "$T/scripts/adopt.sh" --target="$H2" --apply --agent=claude-code \
        >/tmp/adopted-host-sync-h2.log 2>&1 || rc=$?
    echo "$rc" > "$H2.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed on legacy host (rc=$rc)." >&2
        sed 's/^/    /' /tmp/adopted-host-sync-h2.log >&2
    fi
    rm -f "$H2/scripts/lib/template-manifest.sh" \
          "$H2/wiki/Edge-Types.md.template" \
          "$H2/wiki/legacy-host.wiki/Edge-Types.md"
fi

# --- H3: host whose wiki sub-repo ALREADY exists at adopt time (#75) --------
# adopt's init-wiki dispatch short-circuits on wiki/<repo>.wiki/.git, so
# stamping must happen via the already-present branch. The pre-existing
# wiki carries sentinel content that adopt must NOT touch. The committed
# .gitignore rule keeps the wiki sub-repo out of git status so adopt's
# clean-tree guard passes (the same rule adopt's own grant installs).
H3="$STAGE/prewiki-host"
if [ ! -d "$H3/.git" ]; then
    git init -q "$H3"
    git -C "$H3" remote add origin "https://github.com/acme/prewiki-host.git"
    echo "# Prewiki Host" > "$H3/README.md"
    printf 'wiki/*.wiki/\n' > "$H3/.gitignore"
    mkdir -p "$H3/wiki/prewiki-host.wiki"
    git init -q "$H3/wiki/prewiki-host.wiki"
    printf '# SCHEMA\n\nPRE_EXISTING_SCHEMA_SENTINEL\n' \
        > "$H3/wiki/prewiki-host.wiki/SCHEMA_prewiki-host.md"
    printf '# Home\n\nPRE_EXISTING_HOME_SENTINEL\n' \
        > "$H3/wiki/prewiki-host.wiki/Home_prewiki-host.md"
    git -C "$H3" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H3" -c user.email=t@x.invalid -c user.name=t commit -qm "initial"
    rc=0
    bash "$T/scripts/adopt.sh" --target="$H3" --apply --agent=claude-code \
        >/tmp/adopted-host-sync-h3.log 2>&1 || rc=$?
    echo "$rc" > "$H3.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed on prewiki host (rc=$rc)." >&2
        sed 's/^/    /' /tmp/adopted-host-sync-h3.log >&2
    fi
fi

# --- H4: GENUINE legacy host — pre-fix updater + no manifest (#74 review) ---
# H2 exercises the NEW updater's bootstrap; a real pre-fix host runs the
# OLD updater, which sources the manifest at its line 66 BEFORE any fetch,
# so no logic delivered by an update can ever reach it. Constructed
# hermetically from the pinned verbatim artifact
# _fixtures/legacy-update-from-template.sh (byte copy of
# origin/main @ 0eec87c; CI checkouts are depth-1, so extracting the old
# version from git history at run time is not an option).
#
# assertions.sh first OBSERVES the constraint (old updater dies naming the
# manifest), then runs the documented migration — re-adopt --apply --force
# from the template, no host-side tooling required — and finally proves
# the old updater, unblocked by the delivered manifest, syncs itself up
# to the current version.
H4="$STAGE/oldhost"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/_fixtures" && pwd)"
if [ ! -d "$H4/.git" ]; then
    git init -q "$H4"
    git -C "$H4" remote add origin "https://github.com/acme/oldhost.git"
    echo "# Old Host" > "$H4/README.md"
    git -C "$H4" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H4" -c user.email=t@x.invalid -c user.name=t commit -qm "initial"
    rc=0
    bash "$T/scripts/adopt.sh" --target="$H4" --apply --agent=claude-code \
        >/tmp/adopted-host-sync-h4.log 2>&1 || rc=$?
    echo "$rc" > "$H4.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed on old host (rc=$rc)." >&2
        sed 's/^/    /' /tmp/adopted-host-sync-h4.log >&2
    fi
    # Legacy surgery: the pre-fix updater, no manifest, no Edge-Types
    # artifacts — the exact on-disk state a pre-#74 adoption produced.
    cp "$FIXTURES_DIR/legacy-update-from-template.sh" "$H4/scripts/update-from-template.sh"
    chmod +x "$H4/scripts/update-from-template.sh"
    rm -f "$H4/scripts/lib/template-manifest.sh" \
          "$H4/wiki/Edge-Types.md.template" \
          "$H4/wiki/oldhost.wiki/Edge-Types.md"
    # The migration re-adopt requires a clean host tree; legacy hosts have
    # long since committed their adoption, so commit the simulated state.
    git -C "$H4" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H4" -c user.email=t@x.invalid -c user.name=t commit -qm "simulate pre-#74 adoption state"
fi

echo "  adopted-host-sync patch applied: template at $T, hosts at $H, $H2, $H3, $H4."
