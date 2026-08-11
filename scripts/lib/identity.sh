#!/usr/bin/env bash
#
# identity.sh — canonical project-name resolution.
#
# The name has two authoritative sources depending on lifecycle stage,
# and using the wrong one is the root bug this library exists to kill:
#
#   CREATION  (wiki does not exist yet) -> derive from the upstream
#             (origin) repo name. The directory basename is incidental.
#
#   POST-CLONE (wiki already committed)  -> read the name off the on-disk
#             wiki directory. A fork (origin renamed) or a renamed clone
#             makes BOTH the basename and origin wrong here; the committed
#             wiki/<name>.wiki is the only correct source.

# CREATION-TIME resolver. Falls back to the directory basename ONLY when
# no origin is configured (fresh local clone not yet pushed), with a warning
# so the fallback is visible rather than silent.
lw_name_from_origin() {
  local root="${1:?repo root required}" url name=""
  if url="$(lw_origin_url "$root")"; then
    name="$(lw_repo_from_url "$url")"
  fi
  if [[ -z "$name" ]]; then
    name="$(basename "$root")"
    lw_warn "no origin remote; falling back to directory name '$name' for project identity"
  fi
  printf '%s\n' "$name"
}

# POST-CLONE resolver. Reads the name from wiki/*.wiki. Errors on zero or
# multiple matches so the caller fails loud instead of guessing; this also
# subsumes the "wiki not found" existence check the overlays do today.
lw_discover_wiki_name() {
  local root="${1:?repo root required}" d matches=()
  for d in "$root"/wiki/*.wiki; do
    [[ -d "$d" ]] && matches+=("$d")
  done
  case "${#matches[@]}" in
    0) lw_die "no wiki under $root/wiki/*.wiki (run wiki/init-wiki.sh first)" ;;
    1) local base; base="$(basename "${matches[0]}")"; printf '%s\n' "${base%.wiki}" ;;
    *) lw_die "multiple wikis under $root/wiki/ (${matches[*]}); name is ambiguous" ;;
  esac
}
