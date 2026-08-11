#!/usr/bin/env bash
#
# claude.sh — Claude Code integration helpers.
#
# Reproduces how Claude Code maps a working directory to its per-project
# state directory. Behaviour verified empirically (see the shared-lib test,
# which cross-checks every case against an independent reference and against
# a live session's actual project dir):
#
#   slug(cwd) = cwd with every char NOT in [a-zA-Z0-9] replaced by '-'
#               (1:1, runs are NOT collapsed; leading '/' -> leading '-').
#   if len(slug) > 200: slug = slug[0:200] + '-' + base36(abs(hash(cwd)))
#   project dir = <configDir>/projects/<slug>
#   configDir   = $CLAUDE_CONFIG_DIR, else ~/.claude
#
# hash() is a 32-bit string hash (h = h*31 + c, wrapped to a signed int32
# each step) keyed on the RAW cwd, not the sanitized string.
#
# Caveat: this assumes an ASCII path. Non-ASCII bytes are sanitized/hashed
# byte-wise (LC_ALL=C), so a path with multibyte characters can diverge.

# Claude Code config dir: $CLAUDE_CONFIG_DIR, else ~/.claude.
lw_claude_config_dir() {
  printf '%s\n' "${CLAUDE_CONFIG_DIR:-${HOME:?HOME not set}/.claude}"
}

# Integer -> lowercase base36 string.
_lw_base36() {
  local n="$1" out="" d
  local digits="0123456789abcdefghijklmnopqrstuvwxyz"
  if (( n == 0 )); then printf '0\n'; return; fi
  while (( n > 0 )); do
    d=$(( n % 36 )); out="${digits:d:1}$out"; n=$(( n / 36 ))
  done
  printf '%s\n' "$out"
}

# 32-bit string hash of the raw path, as base36(abs(.)). Masks to int32
# each step so bash's 64-bit ints never overflow and the result matches a
# per-step signed-32-bit wrap.
_lw_path_hash36() {
  local s="$1" t=0 i c
  local LC_ALL=C
  for (( i = 0; i < ${#s}; i++ )); do
    printf -v c '%d' "'${s:i:1}"
    t=$(( t * 31 + c ))
    t=$(( t & 0xFFFFFFFF ))
    (( t >= 0x80000000 )) && t=$(( t - 0x100000000 ))
  done
  (( t < 0 )) && t=$(( -t ))
  _lw_base36 "$t"
}

# cwd -> project slug. Pure bash: pattern substitution replaces each
# non-alnum char with '-' (1:1, no run collapsing). LC_ALL=C pins the
# a-z/A-Z/0-9 ranges to ASCII regardless of the caller's locale.
lw_claude_project_slug() {
  local path="${1:?path required}" slug
  local LC_ALL=C
  slug="${path//[!a-zA-Z0-9]/-}"
  if (( ${#slug} > 200 )); then
    slug="${slug:0:200}-$(_lw_path_hash36 "$path")"
  fi
  printf '%s\n' "$slug"
}

# Per-project memory directory: <configDir>/projects/<slug>/memory.
lw_memory_dir() {
  local root="${1:?repo root required}"
  printf '%s\n' "$(lw_claude_config_dir)/projects/$(lw_claude_project_slug "$root")/memory"
}
