#!/usr/bin/env bash
# Assertions: an adopted host's OWN sync tooling must work (#74) and its
# wiki must carry the stamped Edge-Types page (#75).
#
# #74: update-from-template.sh and check-template-version.sh source
# scripts/lib/template-manifest.sh from the HOST tree. If adopt does not
# ship the manifest itself, both die at their source line — the exact
# failure this fixture pins. The template remote for the host-side runs
# is the sandbox-staged template repo (hermetic; no network).
#
# #75: init-wiki stamps wiki/*.md.template from the HOST's wiki/ dir under
# nullglob, so a missing Edge-Types.md.template is a silent no-op and the
# stamped SCHEMA's [Edge-Types] links all dangle.

STAGE="$SANDBOX/adopted-host-sync"
T="$STAGE/template"
H="$STAGE/host"

# patch.sh declines (removes $STAGE) when no template source is available
# (offline, or derived checkout per issue #15).
if [ ! -d "$H" ]; then
    skip "adopted-host-sync assertions" "no template clone available (offline, or run inside a derived project)"
    return 0 2>/dev/null || true
fi

assert "adopt --apply exited 0" \
    "[ \"\$(cat '$H.adopt-rc' 2>/dev/null)\" = '0' ]"

# --- #74: the manifest ships, and the host-side sync tooling runs -----------
assert "host has scripts/lib/template-manifest.sh" \
    "[ -f '$H/scripts/lib/template-manifest.sh' ]"

update_rc=0
( cd "$H" && ./scripts/update-from-template.sh --dry-run --template-url="$T" ) \
    > "$STAGE/update-dry-run.out" 2>&1 || update_rc=$?
assert_eq "host update-from-template.sh --dry-run exit status" "0" "$update_rc"
# The full banner line only prints after the manifest sourced and the
# template fetch succeeded; the pre-fix crash output does not contain it.
assert "host update dry-run printed its report banner" \
    "grep -qF '================ update-from-template ================' '$STAGE/update-dry-run.out'"

check_rc=0
( cd "$H" && ./scripts/check-template-version.sh --template-url="$T" ) \
    > "$STAGE/check-version.out" 2>&1 || check_rc=$?
# rc 0 = in sync, rc 1 = drift: both are completed runs. The pre-fix
# source crash also exits 1, so the banner assertion below is the one
# that separates "reported drift" from "died before reporting".
assert "host check-template-version completed (rc <= 1)" \
    "[ '$check_rc' -le 1 ]"
assert "host check-template-version printed its report banner" \
    "grep -qF '================ check-template-version ================' '$STAGE/check-version.out'"

# --- #75: Edge-Types template ships and gets stamped into the wiki ----------
assert "host received wiki/Edge-Types.md.template" \
    "[ -f '$H/wiki/Edge-Types.md.template' ]"
EDGE="$H/wiki/sync-host.wiki/Edge-Types.md"
assert "adopted wiki has Edge-Types.md (stamped by init-wiki)" \
    "[ -f '$EDGE' ]"
assert "stamped Edge-Types.md has the repo name substituted" \
    "grep -qF 'sync-host' '$EDGE'"
assert "stamped Edge-Types.md has no {{REPO_NAME}} placeholder left" \
    "! grep -qF '{{REPO_NAME}}' '$EDGE'"

# --- #74 migration: legacy host (adopted pre-fix, no manifest on disk) ------
# Its updater must BOOTSTRAP the manifest from the template ref instead of
# dying at the source line, then install the real file via the normal sync
# loop (apply mode). The Edge-Types PAGE is deliberately not asserted here:
# update syncs files, it does not stamp wikis — legacy wikis gain the page
# on their next init-wiki run.
H2="$STAGE/legacy-host"
assert "legacy host staged without the manifest" \
    "[ -d '$H2' ] && [ ! -f '$H2/scripts/lib/template-manifest.sh' ]"
legacy_rc=0
( cd "$H2" && ./scripts/update-from-template.sh --template-url="$T" ) \
    > "$STAGE/legacy-update.out" 2>&1 || legacy_rc=$?
assert_eq "legacy host update-from-template.sh exit status" "0" "$legacy_rc"
assert "legacy update printed its report banner" \
    "grep -qF '================ update-from-template ================' '$STAGE/legacy-update.out'"
assert "legacy update announced the manifest bootstrap" \
    "grep -qi 'bootstrap' '$STAGE/legacy-update.out'"
assert "legacy host now has scripts/lib/template-manifest.sh on disk" \
    "[ -f '$H2/scripts/lib/template-manifest.sh' ]"
assert "restored manifest is byte-equal to the template's" \
    "cmp -s '$H2/scripts/lib/template-manifest.sh' '$T/scripts/lib/template-manifest.sh'"
assert "legacy host got wiki/Edge-Types.md.template back too" \
    "[ -f '$H2/wiki/Edge-Types.md.template' ]"
legacy_check_rc=0
( cd "$H2" && ./scripts/check-template-version.sh --template-url="$T" ) \
    > "$STAGE/legacy-check.out" 2>&1 || legacy_check_rc=$?
assert "legacy host check-template-version completed (rc <= 1)" \
    "[ '$legacy_check_rc' -le 1 ]"
assert "legacy check printed its report banner" \
    "grep -qF '================ check-template-version ================' '$STAGE/legacy-check.out'"

# --- #75: host whose wiki sub-repo already existed at adopt time ------------
# adopt's init-wiki dispatch short-circuits on the existing wiki, so the
# already-present branch must stamp the MISSING template pages itself —
# and must not touch the host's pre-existing wiki content.
H3="$STAGE/prewiki-host"
assert "prewiki adopt --apply exited 0" \
    "[ \"\$(cat '$H3.adopt-rc' 2>/dev/null)\" = '0' ]"
EDGE3="$H3/wiki/prewiki-host.wiki/Edge-Types.md"
assert "prewiki host: Edge-Types.md stamped despite skipped init-wiki" \
    "[ -f '$EDGE3' ]"
assert "prewiki host: stamped page has the repo name substituted" \
    "grep -qF 'prewiki-host' '$EDGE3'"
assert "prewiki host: pre-existing SCHEMA content untouched" \
    "grep -qF 'PRE_EXISTING_SCHEMA_SENTINEL' '$H3/wiki/prewiki-host.wiki/SCHEMA_prewiki-host.md'"
assert "prewiki host: pre-existing Home content untouched" \
    "grep -qF 'PRE_EXISTING_HOME_SENTINEL' '$H3/wiki/prewiki-host.wiki/Home_prewiki-host.md'"

# --- #74 review: GENUINE legacy host (pre-fix updater + no manifest) --------
# The migration under test must not depend on host-side tooling: the old
# updater is the broken part, so the repair is a re-adopt from a current
# template clone.
H4="$STAGE/oldhost"
assert "old host adopt --apply exited 0" \
    "[ \"\$(cat '$H4.adopt-rc' 2>/dev/null)\" = '0' ]"

# The constraint, observed: the pre-fix updater dies at its source line
# BEFORE any fetch. No bootstrap inside the updater can reach this host.
old_rc=0
( cd "$H4" && ./scripts/update-from-template.sh --dry-run --template-url="$T" ) \
    > "$STAGE/oldhost-pre.out" 2>&1 || old_rc=$?
assert "pre-fix updater fails without the manifest (the #74 constraint)" \
    "[ '$old_rc' -ne 0 ]"
assert "pre-fix updater failure names template-manifest.sh" \
    "grep -q 'template-manifest.sh' '$STAGE/oldhost-pre.out'"

# The documented migration is a re-adopt. Without --force the composite
# already-adopted detector refuses — correct, and why the doc says --force.
noforce_rc=0
bash "$T/scripts/adopt.sh" --target="$H4" --apply --agent=claude-code \
    > "$STAGE/oldhost-noforce.out" 2>&1 || noforce_rc=$?
assert "re-adopt without --force is refused on the adopted host" \
    "[ '$noforce_rc' -ne 0 ]"

# Migration: adopt --apply --force ADDs the manifest and the Edge-Types
# template, and stamps the missing wiki page (already-present branch).
force_rc=0
bash "$T/scripts/adopt.sh" --target="$H4" --apply --force --agent=claude-code \
    > "$STAGE/oldhost-force.out" 2>&1 || force_rc=$?
assert_eq "migration adopt --apply --force exit status" "0" "$force_rc"
assert "migration landed scripts/lib/template-manifest.sh" \
    "[ -f '$H4/scripts/lib/template-manifest.sh' ]"
assert "migration landed wiki/Edge-Types.md.template" \
    "[ -f '$H4/wiki/Edge-Types.md.template' ]"
assert "migration stamped Edge-Types.md into the existing wiki" \
    "[ -f '$H4/wiki/oldhost.wiki/Edge-Types.md' ]"
assert "migration left the OLD updater in place (ADD never overwrites)" \
    "! cmp -s '$H4/scripts/update-from-template.sh' '$T/scripts/update-from-template.sh'"

# With the manifest delivered, the OLD updater is unblocked: its source
# line succeeds and its own sync loop brings the host current — including
# replacing itself with the current updater.
post_rc=0
( cd "$H4" && ./scripts/update-from-template.sh --template-url="$T" ) \
    > "$STAGE/oldhost-post.out" 2>&1 || post_rc=$?
assert_eq "old updater with delivered manifest exit status" "0" "$post_rc"
assert "old updater printed its report banner" \
    "grep -qF '================ update-from-template ================' '$STAGE/oldhost-post.out'"
assert "old updater synced ITSELF to the current version" \
    "cmp -s '$H4/scripts/update-from-template.sh' '$T/scripts/update-from-template.sh'"
