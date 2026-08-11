#!/usr/bin/env bash
#
# text.sh — portable, idempotent text patching.
#
# BSD/macOS portability is the reason these exist as canonical helpers:
# in-place sed and appending under a matched line both have GNU-only
# spellings that silently no-op or fail on BSD tools.
#
# History note: this file used to carry the paired <!-- lw:KEY --> sentinel
# helpers (lw_inject_block, lw_replace_block, lw_wrap_section,
# lw_insert_before) that the overlay setup scripts used to patch the host's
# CLAUDE.md. Those writers are retired (the behavioral instructions ship as
# .claude/rules/*.md and .cursor/rules/*.mdc), so the helpers went with them.

# In-place sed that works on GNU and BSD sed alike.
lw_sed_inplace() {
  local expr="$1" file="$2"
  sed -i.bak "$expr" "$file" && rm -f "$file.bak"
}

# Insert a multi-line BLOCK on the line(s) immediately after the first line
# containing NEEDLE. The sed-free counterpart to appending after a matched
# line: `sed 'Na\<newline>text'` is rejected by BSD/macOS sed (it silently
# no-ops), so anything that needs to append under a heading goes through this
# instead. The block is handed to awk via a tempfile + getline rather than -v
# because BSD awk (macOS) rejects newlines in -v assignments and silently
# emits empty output. No trailing blank line is added, which is what list
# registration (e.g. WIKI-INDEX entries) wants.
lw_append_after() {
  local file="$1" needle="$2" block="$3" tmp blockfile
  tmp="$(mktemp)"; blockfile="$(mktemp)"
  printf '%s\n' "$block" > "$blockfile"
  awk -v needle="$needle" -v bf="$blockfile" '
    { print }
    index($0, needle) && !done {
      while ((getline line < bf) > 0) print line
      close(bf); done = 1
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  rm -f "$blockfile"
}
