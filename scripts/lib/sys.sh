#!/usr/bin/env bash
#
# sys.sh — system / tool-portability helpers.
#
# Home for the "this CLI is spelled differently across platforms" shims, so
# each portability decision lives in exactly one place instead of being
# re-derived at every call site.

# Hex SHA-256 digest of a file on stdout. GNU coreutils ships `sha256sum`;
# macOS ships Perl's `shasum` instead. Prefer sha256sum, fall back to
# `shasum -a 256`, and fail loud if neither is present rather than emit an
# empty digest that a caller might compare as "unchanged".
lw_sha256() {
  local file="${1:?file required}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    lw_die "lw_sha256: neither sha256sum nor shasum found on PATH"
  fi
}
