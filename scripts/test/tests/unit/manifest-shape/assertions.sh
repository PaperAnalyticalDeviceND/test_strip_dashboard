#!/usr/bin/env bash
# Assertions for scripts/lib/template-manifest.sh.
#
# The manifest declares which files the template owns and how each is
# synced. The script consumers (update-from-template.sh, check-template-
# version.sh, adopt.sh) trust the contract; these assertions enforce it.
#
# Every manifest call goes through lw_mcall: a subshell that sources the
# manifest in isolation, so a typo in the manifest cannot poison the
# runner's environment.

ROOT="$SANDBOX/manifest-shape"
REPO_ROOT_LIB="$(cd "$HERE/../.." && pwd)"
LW_MANIFEST="$REPO_ROOT_LIB/scripts/lib/template-manifest.sh"

# Template-checkout guard: the tree invariants below (every SUBSTITUTE
# entry still contains {{REPO_NAME}}, every overlay entry exists on disk)
# hold only in the template repo. This harness ships to derived projects
# via "Use this template", where instantiate has already substituted the
# placeholders and pruned the unused overlays — there the invariants are
# legitimately false (observed: 12 spurious fails in a derived project's
# CI). Same discriminator as clone_template's issue-#15 guard: only the
# template checkout carries the one-shot scripts/instantiate.sh.
if [ ! -f "$REPO_ROOT_LIB/scripts/instantiate.sh" ]; then
    skip "manifest-shape assertions" "not a template checkout (derived project; manifest tree-invariants do not apply)"
    return 0 2>/dev/null || true
fi

# Subshell sourcer; stdout is the eval result, exit status is the call's.
# shellcheck source=/dev/null
lw_mcall() { ( set -uo pipefail; source "$LW_MANIFEST"; eval "$1" ); }

# --- Existence + parseability ----------------------------------------------
assert "template-manifest.sh exists"          "[ -f '$LW_MANIFEST' ]"
assert "template-manifest.sh passes bash -n"  "bash -n '$LW_MANIFEST'"
assert "template-manifest.sh sources cleanly" "lw_mcall true"

# --- Arrays are non-empty --------------------------------------------------
for _arr in TEMPLATE_SHARED_INFRA TEMPLATE_OVERLAY_CLAUDE TEMPLATE_OVERLAY_CURSOR \
            TEMPLATE_SUBSTITUTE_FILES TEMPLATE_HOST_OWNED TEMPLATE_ONE_SHOT; do
    assert_eq "$_arr is non-empty" "1" "$(lw_mcall "[ \${#$_arr[@]} -gt 0 ] && echo 1 || echo 0")"
done

# --- Idempotent source guard -----------------------------------------------
# Sourcing twice in the same shell must not duplicate work or rebind state.
assert_eq "double-source preserves shared-infra count" \
    "$(lw_mcall 'echo "${#TEMPLATE_SHARED_INFRA[@]}"')" \
    "$(lw_mcall 'source "$LW_MANIFEST"; echo "${#TEMPLATE_SHARED_INFRA[@]}"' 2>/dev/null || true)"

# --- HOST_OWNED entries have well-formed grants ----------------------------
# Each "path|type" must split into two non-empty halves and resolve to a
# known_grant_type (merge) recognised by the accessor.
HOST_OWNED_ENTRIES="$(lw_mcall 'printf "%s\n" "${TEMPLATE_HOST_OWNED[@]}"')"
while IFS= read -r _entry; do
    [[ -n "$_entry" ]] || continue
    _path="${_entry%%|*}"
    _type="${_entry##*|}"
    assert "HOST_OWNED entry has non-empty path  ($_entry)"  "[ -n '$_path' ]"
    assert "HOST_OWNED entry has non-empty type  ($_entry)"  "[ -n '$_type' ]"
    assert "HOST_OWNED entry has known op type   ($_entry)" \
        "case '$_type' in merge) true ;; *) false ;; esac"
    _resolved="$(lw_mcall "lw_manifest_known_grant_type '$_path'")"
    assert_eq "lw_manifest_known_grant_type('$_path')" "$_type" "$_resolved"
done <<< "$HOST_OWNED_ENTRIES"

# --- HOST_OWNED is disjoint from sync arrays -------------------------------
# A path that is host-owned must not also appear in any sync array; if it
# did, update-from-template would overwrite host content the host is meant
# to own.
for _arr in TEMPLATE_SHARED_INFRA TEMPLATE_OVERLAY_CLAUDE TEMPLATE_OVERLAY_CURSOR; do
    _overlap="$(lw_mcall "
        for ho in \"\${TEMPLATE_HOST_OWNED[@]}\"; do
            p=\"\${ho%%|*}\"
            for s in \"\${$_arr[@]}\"; do
                [[ \"\$s\" == \"\$p\" ]] && echo \"\$p\"
            done
        done")"
    assert "$_arr ∩ HOST_OWNED is empty" "[ -z \"$_overlap\" ]"
done

# --- TEMPLATE_SUBSTITUTE_FILES ⊆ (SHARED_INFRA ∪ OVERLAY_CLAUDE ∪ OVERLAY_CURSOR) ---
# A substitute entry that isn't synced anywhere is dead code; flag it.
_orphan_substitutes="$(lw_mcall "
    for s in \"\${TEMPLATE_SUBSTITUTE_FILES[@]}\"; do
        found=0
        for f in \"\${TEMPLATE_SHARED_INFRA[@]}\" \"\${TEMPLATE_OVERLAY_CLAUDE[@]}\" \"\${TEMPLATE_OVERLAY_CURSOR[@]}\"; do
            [[ \"\$f\" == \"\$s\" ]] && { found=1; break; }
        done
        [[ \$found -eq 0 ]] && echo \"\$s\"
    done")"
assert "TEMPLATE_SUBSTITUTE_FILES ⊆ sync arrays (no orphans)" "[ -z \"$_orphan_substitutes\" ]"

# --- Every TEMPLATE_SUBSTITUTE_FILES entry actually contains {{REPO_NAME}} -
# This is the load-bearing check that catches the inverse drift: someone
# adds a path to SUBSTITUTE_FILES that doesn't have the marker. Skip if the
# template root copy is missing (would be a separate failure).
while IFS= read -r _s; do
    [[ -n "$_s" ]] || continue
    if [[ -f "$REPO_ROOT_LIB/$_s" ]]; then
        assert "SUBSTITUTE entry contains {{REPO_NAME}}: $_s" \
            "grep -qF '{{REPO_NAME}}' '$REPO_ROOT_LIB/$_s'"
    else
        skip "SUBSTITUTE entry presence in template tree: $_s" "template file not present in this checkout"
    fi
done < <(lw_mcall 'printf "%s\n" "${TEMPLATE_SUBSTITUTE_FILES[@]}"')

# --- Every manifest path actually exists in the template tree --------------
# Catches the drift the previous PR cycle suffered from twice (overlay
# template added, manifest forgotten).
for _arr in TEMPLATE_SHARED_INFRA TEMPLATE_OVERLAY_CLAUDE TEMPLATE_OVERLAY_CURSOR; do
    while IFS= read -r _path; do
        [[ -n "$_path" ]] || continue
        assert "$_arr entry exists in template tree: $_path" \
            "[ -e '$REPO_ROOT_LIB/$_path' ]"
    done < <(lw_mcall "printf '%s\n' \"\${$_arr[@]}\"")
done

# --- Accessor: lw_manifest_needs_substitution ------------------------------
# Truth-table check: the first SUBSTITUTE entry is in, llm-wiki.md is not.
_first_sub="$(lw_mcall 'printf "%s\n" "${TEMPLATE_SUBSTITUTE_FILES[0]}"')"
lw_mcall "lw_manifest_needs_substitution '$_first_sub'"; RC=$?
assert "needs_substitution returns 0 for a SUBSTITUTE entry ($_first_sub)" "[ $RC -eq 0 ]"
lw_mcall "lw_manifest_needs_substitution 'llm-wiki.md'"; RC=$?
assert "needs_substitution returns non-zero for a non-SUBSTITUTE path"      "[ $RC -ne 0 ]"

# --- Accessor: lw_manifest_assemble_active_files ---------------------------
# Counts (used in three assertions below).
N_SHARED="$(lw_mcall 'echo "${#TEMPLATE_SHARED_INFRA[@]}"')"
N_CLAUDE="$(lw_mcall 'echo "${#TEMPLATE_OVERLAY_CLAUDE[@]}"')"
N_CURSOR="$(lw_mcall 'echo "${#TEMPLATE_OVERLAY_CURSOR[@]}"')"
N_SHARED_PLUS_CLAUDE="$((N_SHARED + N_CLAUDE))"
N_SHARED_PLUS_CURSOR="$((N_SHARED + N_CURSOR))"

# Mode A: agent=claude-code, repo_root empty (adopt's call shape).
N_A="$(lw_mcall "lw_manifest_assemble_active_files '' 'claude-code'" | wc -l | tr -d ' ')"
assert_eq "assemble(agent=claude-code) = SHARED + OVERLAY_CLAUDE" "$N_SHARED_PLUS_CLAUDE" "$N_A"

# Mode B: agent=cursor, repo_root empty.
N_B="$(lw_mcall "lw_manifest_assemble_active_files '' 'cursor'" | wc -l | tr -d ' ')"
assert_eq "assemble(agent=cursor) = SHARED + OVERLAY_CURSOR" "$N_SHARED_PLUS_CURSOR" "$N_B"

# Mode C: agent=none (literally any non-matching string + empty repo_root)
# yields just SHARED. Adopt's --agent=none also hits this branch.
N_C="$(lw_mcall "lw_manifest_assemble_active_files '' 'none'" | wc -l | tr -d ' ')"
assert_eq "assemble(agent=none) = SHARED only"                "$N_SHARED"              "$N_C"

# Mode D: detection on host with .claude/ (update/check's call shape).
N_D="$(lw_mcall "lw_manifest_assemble_active_files '$ROOT/host-with-claude' ''" | wc -l | tr -d ' ')"
assert_eq "assemble(detect) host-with-claude/.claude  = SHARED + OVERLAY_CLAUDE" \
    "$N_SHARED_PLUS_CLAUDE" "$N_D"

# Mode E: detection on host with .cursor/.
N_E="$(lw_mcall "lw_manifest_assemble_active_files '$ROOT/host-with-cursor' ''" | wc -l | tr -d ' ')"
assert_eq "assemble(detect) host-with-cursor/.cursor  = SHARED + OVERLAY_CURSOR" \
    "$N_SHARED_PLUS_CURSOR" "$N_E"

# Mode F: detection on a bare host with neither overlay = SHARED only.
N_F="$(lw_mcall "lw_manifest_assemble_active_files '$ROOT/host-bare' ''" | wc -l | tr -d ' ')"
assert_eq "assemble(detect) host-bare                 = SHARED only" "$N_SHARED" "$N_F"

# --- .gitignore is no longer a grant target --------------------------------
# The wiki sub-repo ignore rule ships as wiki/.gitignore (SHARED_INFRA);
# the host's root .gitignore must not resolve to any grant type.
assert_eq "known_grant_type(.gitignore) is empty (rule moved to wiki/.gitignore)" "" \
    "$(lw_mcall "lw_manifest_known_grant_type '.gitignore'")"

# --- CLAUDE.md is no longer a grant target ----------------------------------
# The managed-block grant is retired: the behavioral instructions ship as
# .claude/rules/*.md overlay files and no script writes the host's CLAUDE.md.
assert_eq "known_grant_type(CLAUDE.md) is empty (managed-block grant retired)" "" \
    "$(lw_mcall "lw_manifest_known_grant_type 'CLAUDE.md'")"
assert "CLAUDE.md.template is gone from the template tree" \
    "[ ! -e '$REPO_ROOT_LIB/CLAUDE.md.template' ]"
assert "CLAUDE.md.template is gone from TEMPLATE_ONE_SHOT" \
    "! lw_mcall 'printf \"%s\n\" \"\${TEMPLATE_ONE_SHOT[@]}\"' | grep -qxF 'CLAUDE.md.template'"

# --- .cursorrules.template is retired ---------------------------------------
# The single-file Cursor fallback is removed: Cursor reads .cursor/rules/*.mdc
# since 0.45 and marks .cursorrules legacy, so the overlay ships only .mdc.
assert ".cursorrules.template is gone from the template tree" \
    "[ ! -e '$REPO_ROOT_LIB/.cursorrules.template' ]"
assert ".cursorrules.template is gone from TEMPLATE_ONE_SHOT" \
    "! lw_mcall 'printf \"%s\n\" \"\${TEMPLATE_ONE_SHOT[@]}\"' | grep -qxF '.cursorrules.template'"
assert "wiki/.gitignore is in TEMPLATE_SHARED_INFRA" \
    "lw_mcall 'printf \"%s\n\" \"\${TEMPLATE_SHARED_INFRA[@]}\"' | grep -qxF 'wiki/.gitignore'"
assert "template's wiki/.gitignore carries the *.wiki/ rule" \
    "grep -qxF '*.wiki/' '$REPO_ROOT_LIB/wiki/.gitignore'"

# --- Sync trees (TEMPLATE_SYNC_TREES + lw_manifest_tree_files, #90) --------
# Membership is resolved at run time, so the invariants here are about the
# declarations and the accessor, not a file list.
assert_eq "TEMPLATE_SYNC_TREES is non-empty" "1" \
    "$(lw_mcall "[ \${#TEMPLATE_SYNC_TREES[@]} -gt 0 ] && echo 1 || echo 0")"

# Every declared tree exists as a directory in the template checkout.
_missing_trees="$(lw_mcall "
    for t in \"\${TEMPLATE_SYNC_TREES[@]}\"; do
        [[ -d '$REPO_ROOT_LIB'/\$t ]] || echo \"\$t\"
    done")"
assert "every sync tree exists in the template checkout" "[ -z \"$_missing_trees\" ]"

# No static entry may live under a declared tree: that would be double
# ownership (the tree resolver and the static list would both sync it).
_tree_overlap="$(lw_mcall "
    for t in \"\${TEMPLATE_SYNC_TREES[@]}\"; do
        for f in \"\${TEMPLATE_SHARED_INFRA[@]}\" \"\${TEMPLATE_OVERLAY_CLAUDE[@]}\" \"\${TEMPLATE_OVERLAY_CURSOR[@]}\"; do
            case \"\$f\" in \"\$t\"/*) echo \"\$f\";; esac
        done
    done")"
assert "no static manifest entry lives under a sync tree" "[ -z \"$_tree_overlap\" ]"

# The dir-mode accessor enumerates real members from a checkout.
assert "tree_files dir-mode lists the harness runner" \
    "lw_mcall \"lw_manifest_tree_files dir '$REPO_ROOT_LIB'\" | grep -qx 'scripts/test/run.sh'"
assert "tree_files dir-mode returns a substantial member set" \
    "[ \"$(lw_mcall "lw_manifest_tree_files dir '$REPO_ROOT_LIB'" | wc -l | tr -d ' ')\" -gt 50 ]"

# --- Claude rule files ship in the overlay, name-agnostic -------------------
# .claude/rules/*.md carry the template's behavioral instructions without
# touching the host's CLAUDE.md. Adopt ADDs files verbatim (no substitution
# pass), so a {{REPO_NAME}} marker in a rule would land unstamped on adopted
# hosts; the name-agnostic contract below is what keeps them correct there.
for _rule in .claude/rules/wiki-as-memory.md .claude/rules/memory-boundary.md; do
    assert "rule is in TEMPLATE_OVERLAY_CLAUDE: $_rule" \
        "lw_mcall 'printf \"%s\n\" \"\${TEMPLATE_OVERLAY_CLAUDE[@]}\"' | grep -qxF '$_rule'"
    assert "rule is NOT in TEMPLATE_SUBSTITUTE_FILES: $_rule" \
        "! lw_mcall 'printf \"%s\n\" \"\${TEMPLATE_SUBSTITUTE_FILES[@]}\"' | grep -qxF '$_rule'"
    assert "rule carries no {{REPO_NAME}} marker (name-agnostic): $_rule" \
        "! grep -qF '{{REPO_NAME}}' '$REPO_ROOT_LIB/$_rule'"
done
