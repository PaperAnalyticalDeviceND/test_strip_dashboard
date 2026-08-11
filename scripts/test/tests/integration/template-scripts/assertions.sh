#!/usr/bin/env bash
# Assertions: run the real update-from-template.sh / check-template-version.sh
# against staged fixtures, verifying the chunk-04 shared-library wiring:
#   F1/F2 name discovered from the on-disk wiki, not the clone-dir basename;
#   F5   template branch DETECTED (works against a trunk-only template);
#   F6   a pre-existing 'template' remote pointing elsewhere is rejected;
#   F12  the scripts run (sha comparison via lw_sha256).
#
# All remotes are local paths, so the runs are hermetic. Git identity for the
# scripts' internal git calls comes from the harness-wide hermetic env
# (sandbox_git_env), inherited here and by the scripts under test.

STAGE="$SANDBOX/template-scripts"
# assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
REPO_ROOT_TS="$(cd "$HERE/../.." && pwd)"
UPDATE="$REPO_ROOT_TS/scripts/update-from-template.sh"
CHECK="$REPO_ROOT_TS/scripts/check-template-version.sh"

run_in() {  # run_in <dir> <logfile> <script> [args...]
    local dir="$1" log="$2"; shift 2
    ( cd "$dir" && bash "$@" ) >"$log" 2>&1
}

assert "update-from-template.sh passes bash -n"   "bash -n '$UPDATE'"
assert "check-template-version.sh passes bash -n" "bash -n '$CHECK'"

# --- F1/F2 + F12: update substitutes the WIKI name (widget), not basename ---
UP_LOG="$STAGE/up.log"
run_in "$STAGE/up-clone" "$UP_LOG" "$UPDATE" --template-url="$STAGE/template-main"; RC=$?
assert "update: run exits 0 against template-main" "[ $RC -eq 0 ]"
UPF="$STAGE/up-clone/.claude/skills/wiki-experiment/SKILL.md"
assert "F1/F2: substitution uses the wiki name (widget)" "grep -q 'command for widget' '$UPF'"
assert "F1/F2: no {{REPO_NAME}} left in the synced file"  "! grep -q '{{REPO_NAME}}' '$UPF'"
assert "F1/F2: clone-dir basename (up-clone) NOT used"    "! grep -q 'up-clone' '$UPF'"

# --- F5: branch detected, not hardcoded main (template-trunk has no main) ---
BR_LOG="$STAGE/br.log"
run_in "$STAGE/br-clone" "$BR_LOG" "$UPDATE" --template-url="$STAGE/template-trunk"; RC=$?
assert "F5: update exits 0 against a trunk-only template" "[ $RC -eq 0 ]"
BRF="$STAGE/br-clone/.claude/skills/wiki-experiment/SKILL.md"
assert "F5: file synced from the detected (trunk) branch" "grep -q 'command for widget' '$BRF'"

# --- F6: guard rejects a pre-existing 'template' remote pointing elsewhere ---
GD_LOG="$STAGE/gd.log"
run_in "$STAGE/gd-clone" "$GD_LOG" "$UPDATE" --template-url="$STAGE/template-main"; RC=$?
assert "F6: guard makes the run exit non-zero" "[ $RC -ne 0 ]"
assert_contains "F6: guard explains it is refusing the wrong remote" "$GD_LOG" "refusing to fetch"
GDF="$STAGE/gd-clone/.claude/skills/wiki-experiment/SKILL.md"
assert "F6: local file untouched when the guard fires" "grep -q 'stale local content' '$GDF'"

# --- F1/F2 in the second script: check reports the wiki name (gizmo) ---
CK_LOG="$STAGE/ck.log"
run_in "$STAGE/ck-clone" "$CK_LOG" "$CHECK" --template-url="$STAGE/template-main"; RC=$?
assert_contains "F1/F2: check reports the wiki name (gizmo)" "$CK_LOG" '\(gizmo\)'
assert "F1/F2: check does NOT report the basename (ck-clone)" "! grep -qF '(ck-clone)' '$CK_LOG'"
