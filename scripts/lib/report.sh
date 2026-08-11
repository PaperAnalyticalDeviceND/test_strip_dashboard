#!/usr/bin/env bash
#
# report.sh — structured logging + change tracking.
#
# Replaces the ad-hoc REPORT-string pattern matching that let a
# settings.json-only change slip past the "did anything change?" check
# (a merge that reported "merged ..." matched none of the change keywords).
# Callers record outcomes through lw_record_change / lw_record_skip;
# lw_changed_p answers the commit-prompt question without grepping
# human-readable strings.
#
# The record functions are store-only: they accumulate state but emit
# nothing, so a caller that prints one summary at the end (lw_print_report)
# does not get each line echoed twice. stdout is reserved for function
# return values, so lw_info/warn/die go to stderr.

lw_info() { printf '%s\n' "$*" >&2; }
lw_warn() { printf 'warning: %s\n' "$*" >&2; }

# Print to stderr and exit non-zero. The ONLY function in the library
# permitted to exit; everything else returns status so callers stay in
# control.
lw_die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# One report buffer in insertion order; entries are prefixed '+' (change)
# or '.' (skip). A separate counter answers lw_changed_p so it never has to
# parse the buffer.
_LW_REPORT=()
_LW_CHANGED=0

# Record a mutation that happened (file written, hook merged, block
# injected). The label is free text for the human-facing report only;
# the change-detection logic never parses it.
lw_record_change() { _LW_REPORT+=("+ $1"); _LW_CHANGED=1; }

# Record a no-op (already present, already up to date, nothing to do).
lw_record_skip() { _LW_REPORT+=(". $1"); }

# True iff at least one change was recorded this run.
lw_changed_p() { [[ $_LW_CHANGED -eq 1 ]]; }

# Emit the accumulated report on stdout, in the order recorded. The
# ${arr[@]+...} guard keeps empty-array expansion safe under `set -u` on
# bash 3.2 (macOS system bash).
lw_print_report() {
  local line
  for line in ${_LW_REPORT[@]+"${_LW_REPORT[@]}"}; do printf ' %s\n' "$line"; done
}
