#!/usr/bin/env bash
# Assertions for the shared bash library (scripts/lib/*.sh).
#
# Every library call goes through lw_call, which sources the library in an
# isolated subshell. This is mandatory here: assertions.sh is *sourced* by
# run.sh, and lib functions may call lw_die (which exits) — invoking one
# directly would kill the whole test runner.

ROOT="$SANDBOX/shared-lib"
# assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
REPO_ROOT_LIB="$(cd "$HERE/../.." && pwd)"
LW_COMMON="$REPO_ROOT_LIB/scripts/lib/common.sh"

# Run a library expression in an isolated subshell; stdout is the result,
# exit status is the expression's status.
# shellcheck source=/dev/null
lw_call() { ( set -uo pipefail; source "$LW_COMMON"; eval "$1" ); }

# --- Sanity: every module exists, parses, and the umbrella sources cleanly ---
for _f in common report sys git identity text claude; do
    assert "scripts/lib/$_f.sh exists"         "[ -f '$REPO_ROOT_LIB/scripts/lib/$_f.sh' ]"
    assert "scripts/lib/$_f.sh passes bash -n" "bash -n '$REPO_ROOT_LIB/scripts/lib/$_f.sh'"
done
assert "common.sh sources cleanly" "lw_call true"

# --- git.sh: lw_repo_slug / owner / repo (host-agnostic) ---
assert_eq "slug: https .git"          "acme/widget" "$(lw_call "lw_repo_slug 'https://github.com/acme/widget.git'")"
assert_eq "slug: https no .git"       "acme/widget" "$(lw_call "lw_repo_slug 'https://github.com/acme/widget'")"
assert_eq "slug: scp-style ssh"       "acme/widget" "$(lw_call "lw_repo_slug 'git@github.com:acme/widget.git'")"
assert_eq "slug: ssh:// with port"    "org/proj"    "$(lw_call "lw_repo_slug 'ssh://git@example.com:2222/org/proj'")"
assert_eq "repo: gitlab subgroup"     "repo"        "$(lw_call "lw_repo_from_url 'git@gitlab.com:group/sub/repo.git'")"
assert_eq "owner: from https"         "acme"        "$(lw_call "lw_owner_from_url 'https://github.com/acme/widget.git'")"

# --- git.sh: lw_wiki_url (both suffix forms collapse to one result) ---
assert_eq "wiki_url: .git form"    "https://github.com/acme/widget.wiki.git" "$(lw_call "lw_wiki_url 'https://github.com/acme/widget.git'")"
assert_eq "wiki_url: no-.git form" "https://github.com/acme/widget.wiki.git" "$(lw_call "lw_wiki_url 'https://github.com/acme/widget'")"
assert_eq "wiki_url: scp-style github" "git@github.com:acme/widget.wiki.git" "$(lw_call "lw_wiki_url 'git@github.com:acme/widget.git'")"
assert_eq "wiki_url: github enterprise host accepted" "https://github.corp.example/acme/widget.wiki.git" \
    "$(lw_call "lw_wiki_url 'https://github.corp.example/acme/widget.git'")"
# D1: non-GitHub host fails loud instead of emitting a wrong URL.
lw_call "lw_wiki_url 'https://gitlab.com/acme/widget.git'" >/dev/null 2>&1; RC=$?
assert "wiki_url: non-github host (gitlab) exits non-zero" "[ $RC -ne 0 ]"
lw_call "lw_wiki_url 'git@gitlab.com:acme/widget.git'" >/dev/null 2>&1; RC=$?
assert "wiki_url: non-github host (scp gitlab) exits non-zero" "[ $RC -ne 0 ]"

# --- git.sh: lw_repo_root / lw_origin_url ---
assert_eq "repo_root resolves toplevel" "$(cd "$ROOT/repo-https" && pwd -P)" "$(lw_call "cd '$ROOT/repo-https' && lw_repo_root")"
lw_call "cd '$ROOT/notrepo' && lw_repo_root" >/dev/null 2>&1; RC=$?
assert "repo_root outside a repo exits non-zero" "[ $RC -ne 0 ]"
assert_eq "origin_url: https" "https://github.com/acme/widget.git" "$(lw_call "lw_origin_url '$ROOT/repo-https'")"
lw_call "lw_origin_url '$ROOT/repo-noorigin'" >/dev/null 2>&1; RC=$?
assert "origin_url with no origin exits non-zero" "[ $RC -ne 0 ]"

# --- identity.sh: creation-time resolver (from origin) ---
assert_eq "name_from_origin: https" "widget" "$(lw_call "lw_name_from_origin '$ROOT/repo-https'")"
assert_eq "name_from_origin: ssh"   "widget" "$(lw_call "lw_name_from_origin '$ROOT/repo-ssh'")"
assert_eq "name_from_origin: no origin falls back to basename" "repo-noorigin" \
    "$(lw_call "lw_name_from_origin '$ROOT/repo-noorigin' 2>/dev/null")"

# --- identity.sh: post-clone resolver (discover on-disk wiki) ---
assert_eq "discover_wiki_name: exactly one wiki" "my-proj" "$(lw_call "lw_discover_wiki_name '$ROOT/wiki-one'")"
lw_call "lw_discover_wiki_name '$ROOT/wiki-none'" >/dev/null 2>&1; RC=$?
assert "discover_wiki_name: zero wikis exits non-zero" "[ $RC -ne 0 ]"
lw_call "lw_discover_wiki_name '$ROOT/wiki-many'" >/dev/null 2>&1; RC=$?
assert "discover_wiki_name: multiple wikis exits non-zero" "[ $RC -ne 0 ]"

# --- git.sh: lw_default_branch (detected, not hardcoded to main/master) ---
assert_eq "default_branch detects 'trunk'" "trunk" "$(lw_call "lw_default_branch origin '$ROOT/branch/clone'")"

# --- git.sh: lw_ensure_remote (add when absent; accept same repo; reject other) ---
lw_call "lw_ensure_remote template 'https://github.com/acme/widget.git' '$ROOT/ensure/none'" >/dev/null 2>&1; RC=$?
assert "ensure_remote: adds the remote when absent (exit 0)" "[ $RC -eq 0 ]"
assert_eq "ensure_remote: records the expected URL" "https://github.com/acme/widget.git" \
    "$(git -C "$ROOT/ensure/none" remote get-url template 2>/dev/null)"
lw_call "lw_ensure_remote template 'git@github.com:acme/widget.git' '$ROOT/ensure/has'" >/dev/null 2>&1; RC=$?
assert "ensure_remote: accepts the same repo in another URL form (exit 0)" "[ $RC -eq 0 ]"
lw_call "lw_ensure_remote template 'https://github.com/acme/other.git' '$ROOT/ensure/has'" >/dev/null 2>&1; RC=$?
assert "ensure_remote: rejects a different repo (exit non-zero)" "[ $RC -ne 0 ]"

# --- claude.sh: project-dir encoding (faithful port of Claude Code NS/tr/MU) ---
# Every non-alnum char sanitizes to '-' (the old tr '/._' was wrong for
# spaces, '+', parens, etc. — those would have produced an unreadable dir).
assert_eq "slug: spaces/dots/underscores/plus all -> dash" "-home-u-my-project-v2-final-1" \
    "$(lw_call "lw_claude_project_slug '/home/u/my project.v2_final+1'")"
assert_eq "slug: assorted punctuation -> dash" "-weird--paren--tilde-at-hash" \
    "$(lw_call "lw_claude_project_slug '/weird/(paren)~tilde@at#hash'")"
# $CLAUDE_CONFIG_DIR overrides ~/.claude.
assert_eq "memory_dir honors CLAUDE_CONFIG_DIR" "/cfg/projects/-a-b/memory" \
    "$(lw_call "CLAUDE_CONFIG_DIR=/cfg lw_memory_dir /a/b")"
assert_eq "memory_dir defaults to HOME/.claude" "/fake-home/.claude/projects/-a-b/memory" \
    "$(lw_call "HOME=/fake-home; unset CLAUDE_CONFIG_DIR; lw_memory_dir /a/b")"

# >200 sanitized chars: truncate to 200 + '-' + base36(int32 hash of RAW path).
# Cross-checked against an independent Python reimplementation of the encoding.
LONGP="/home/jsweet/$(printf 'a%.0s' $(seq 1 220))/proj"
if command -v python3 >/dev/null 2>&1; then
    EXP_SLUG="$(python3 - "$LONGP" <<'PY'
import sys, re
e = sys.argv[1]
def h(e):
    t = 0
    for ch in e:
        t = (t*31 + ord(ch)) & 0xFFFFFFFF
        if t >= 0x80000000: t -= 0x100000000
    n = abs(t)
    if n == 0: return "0"
    d = "0123456789abcdefghijklmnopqrstuvwxyz"; s = ""
    while n > 0: s = d[n%36] + s; n //= 36
    return s
slug = re.sub(r'[^a-zA-Z0-9]', '-', e)
if len(slug) > 200: slug = slug[:200] + "-" + h(e)
print(slug)
PY
)"
    assert_eq "slug(long): truncate+hash matches reference impl" "$EXP_SLUG" \
        "$(lw_call "lw_claude_project_slug '$LONGP'")"
else
    skip "slug(long): truncate+hash vs reference impl" "python3 not available"
fi

# --- sys.sh: lw_sha256 (sha256sum preferred, shasum -a 256 fallback) ---
# Known digest of "llm-wiki\n" (printf 'llm-wiki\n' | sha256sum).
SHA_EXPECT="164d626053db60f0f0b9b6c6cba8eabd98d82d81a8f491e90e0b81ed0276c7a1"
assert_eq "sha256: matches a known digest" "$SHA_EXPECT" \
    "$(lw_call "lw_sha256 '$ROOT/sha/input.txt'")"
# Fallback: with sha256sum absent from PATH (fakebin has only shasum + awk),
# lw_sha256 must take the shasum branch and produce the same digest.
if [ -x "$ROOT/sha-fakebin/shasum" ]; then
    assert_eq "sha256: shasum fallback matches when sha256sum absent" "$SHA_EXPECT" \
        "$(lw_call "PATH='$ROOT/sha-fakebin'; lw_sha256 '$ROOT/sha/input.txt'")"
else
    skip "sha256: shasum fallback" "shasum not available on this host"
fi

# --- report.sh: change tracking without parsing report strings ---
lw_call "lw_changed_p"; RC=$?
assert "changed_p false when nothing recorded" "[ $RC -ne 0 ]"
lw_call "lw_record_change one >/dev/null 2>&1; lw_changed_p"; RC=$?
assert "changed_p true after a change is recorded" "[ $RC -eq 0 ]"

# --- text.sh: lw_sed_inplace (portable in-place edit; init-wiki relies on it) ---
SEDF="$ROOT/sed.md"

# s/// substitution lands and leaves no .bak behind.
printf 'alpha\nbeta\ngamma\n' > "$SEDF"
lw_call "lw_sed_inplace 's/beta/BETA/' '$SEDF'" >/dev/null 2>&1
assert_contains "sed_inplace: substitution applied" "$SEDF" '^BETA$'
assert "sed_inplace: leaves no .bak file" "[ ! -e '$SEDF.bak' ]"

# --- text.sh: lw_append_after (insert under a heading; init-wiki's WIKI-INDEX
# registration). Replaces a sed 'Na\' append that BSD/macOS sed silently
# no-ops, so this is the exact case the macos CI job regressed on. ---
APPF="$ROOT/append.md"
printf '# Index\n\n## Wikis\n- [[existing]] — old\n\nfooter\n' > "$APPF"
lw_call "lw_append_after '$APPF' '## Wikis' '- [[new]] — fresh'" >/dev/null 2>&1
assert_contains "append_after: line inserted" "$APPF" '^- \[\[new\]\] — fresh$'
assert "append_after: lands directly under the heading" \
    "awk '/^## Wikis\$/{h=NR} /^- \[\[new\]\]/{a=NR} END{exit !(h>0 && a==h+1)}' '$APPF'"
assert_contains "append_after: pre-existing entry preserved" "$APPF" '^- \[\[existing\]\] — old$'
assert_contains "append_after: content below the heading preserved" "$APPF" '^footer$'

# The paired-sentinel helpers (lw_inject_block, lw_replace_block,
# lw_wrap_section, lw_insert_before) are retired along with the CLAUDE.md
# writers that consumed them; their tests went with them.
