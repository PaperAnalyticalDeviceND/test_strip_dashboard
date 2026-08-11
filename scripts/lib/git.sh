#!/usr/bin/env bash
#
# git.sh — git remote / URL / branch helpers.
#
# Host-agnostic where it costs nothing. The few GitHub-specific
# assumptions (wiki URL scheme) are isolated in one function and flagged,
# so the "do we support non-GitHub hosts?" policy question has exactly one
# place to be answered later.

# Repo root, robustly. Fails LOUD instead of falling back to $PWD, so a
# script invoked outside a repo gets a clear error rather than silently
# building paths against the wrong directory.
lw_repo_root() {
  local root
  root="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" \
    || lw_die "not inside a git repository"
  printf '%s\n' "$root"
}

# Origin URL on stdout; empty output + nonzero return when origin is unset.
lw_origin_url() {
  local url
  url="$(git -C "${1:-.}" remote get-url origin 2>/dev/null)" || return 1
  printf '%s\n' "$url"
}

# owner/repo slug from any git URL. Strips scheme+host generically rather
# than matching github.com, so it survives gitlab/gitea/self-hosted/ssh:
#   https://host/owner/repo(.git)   git@host:owner/repo(.git)
#   ssh://git@host[:port]/owner/repo(.git)
# Caveat: GitLab subgroups (host/group/sub/repo) yield owner=group; the
# repo component (last path element) is still correct.
lw_repo_slug() {
  local url="$1"
  url="${url%.git}"; url="${url%/}"
  case "$url" in
    *://*) url="${url#*://}"; url="${url#*@}"; url="${url#*/}" ;;  # scheme[user@]host/owner/repo
    *@*:*) url="${url#*@}";   url="${url#*:}" ;;                   # scp-style user@host:owner/repo
  esac
  printf '%s\n' "$url"
}

lw_owner_from_url() { local s; s="$(lw_repo_slug "$1")"; printf '%s\n' "${s%%/*}"; }
lw_repo_from_url()  { local s; s="$(lw_repo_slug "$1")"; printf '%s\n' "${s##*/}"; }

# GitHub wiki clone URL from an origin URL. Single canonical implementation
# replacing the two that had drifted: init-wiki.sh used `sed 's/.git$/...'`
# which is a no-op on a suffix-less URL; instantiate.sh handled that case.
# strip-then-append covers both.
#
# The `<repo>.wiki.git` scheme is GitHub-specific (it also holds for GitHub
# Enterprise, whose host names contain "github"). GitLab, Gitea, and other
# hosts use entirely different wiki schemes, so deriving this URL for them
# would emit a plausible-looking address that does not exist. Policy (D1):
# fail loud on a non-GitHub host rather than return a wrong URL silently.
# The host check is a heuristic ("github" in the host component); a host
# that contains "github" but is not GitHub is accepted, which is the safe
# direction (the user opted into --github).
lw_wiki_url() {
  local url="$1" rest host
  rest="$url"
  case "$rest" in
    *://*) rest="${rest#*://}"; rest="${rest#*@}" ;;  # scheme://[user@]host/...
    *@*:*) rest="${rest#*@}" ;;                        # scp-style user@host:...
  esac
  host="${rest%%[:/]*}"  # up to the first ':' or '/'
  case "$host" in
    *github*) : ;;
    *) lw_die "lw_wiki_url: GitHub-only; refusing to derive a wiki URL for non-GitHub host '$host' (origin: $url)" ;;
  esac
  url="${url%.git}"
  printf '%s\n' "${url}.wiki.git"
}

# Ensure a named remote exists and points at the expected repo. Adds it when
# absent; when already present, compares by normalized owner/repo slug so an
# ssh-vs-https spelling of the SAME repo is accepted, but a genuinely different
# repo fails loud rather than silently fetching from the wrong place (F6).
# The slug of a local-path remote (used in tests) is its bare path, so a
# different path is correctly rejected too.
lw_ensure_remote() {
  local name="$1" expected="$2" dir="${3:-.}" current
  if current="$(git -C "$dir" remote get-url "$name" 2>/dev/null)"; then
    if [[ "$(lw_repo_slug "$current")" != "$(lw_repo_slug "$expected")" ]]; then
      lw_die "remote '$name' points at '$current', not the expected '$expected'; refusing to fetch from a different repo (remove the remote or pass the matching URL)"
    fi
  else
    git -C "$dir" remote add "$name" "$expected"
  fi
}

# Default branch of a remote, DETECTED not hardcoded (mirrors the fix
# already in protocol.sh). Tries the locally-known remote HEAD symref
# first, then asks the remote over the network. Empty output + nonzero
# return when undetectable, so the caller chooses a fallback explicitly
# instead of silently assuming main vs master.
lw_default_branch() {
  local remote="${1:-origin}" dir="${2:-.}" head
  head="$(git -C "$dir" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null)" \
    && { printf '%s\n' "${head#"$remote/"}"; return 0; }
  head="$(git -C "$dir" remote show "$remote" 2>/dev/null \
            | awk '/HEAD branch:/ {print $NF; exit}')"
  [[ -n "$head" && "$head" != "(unknown)" ]] && { printf '%s\n' "$head"; return 0; }
  return 1
}
