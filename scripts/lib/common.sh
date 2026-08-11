#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# common.sh — umbrella loader for the llm-wiki shared bash library.
#
# Source this once; it pulls in the focused modules under scripts/lib/.
# All public functions are namespaced lw_*. Library discipline:
#   - functions return DATA on stdout, STATUS via `return`;
#   - only lw_die exits the process;
#   - declare then assign when a command's exit status matters
#     (`local x=$(cmd)` masks it).
#
# Locating this file from a consumer (use BASH_SOURCE, never $0):
#   HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$HERE/lib/common.sh"                 # scripts/*.sh
#   source "$HERE/../scripts/lib/common.sh"      # wiki/init-wiki.sh
#   source "$HERE/../../../scripts/lib/common.sh"# wiki/agents/*/setup.sh
#

# Idempotent: safe to source more than once (e.g. a script that also
# sources install-feature.sh, which may pull this in too).
[[ -n "${_LW_COMMON_SOURCED:-}" ]] && return 0
_LW_COMMON_SOURCED=1

_LW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Order matters: report.sh defines lw_die/lw_warn used by the others.
# shellcheck source=report.sh
source "$_LW_LIB_DIR/report.sh"
# shellcheck source=sys.sh
source "$_LW_LIB_DIR/sys.sh"
# shellcheck source=git.sh
source "$_LW_LIB_DIR/git.sh"
# shellcheck source=identity.sh
source "$_LW_LIB_DIR/identity.sh"
# shellcheck source=text.sh
source "$_LW_LIB_DIR/text.sh"
# shellcheck source=claude.sh
source "$_LW_LIB_DIR/claude.sh"
