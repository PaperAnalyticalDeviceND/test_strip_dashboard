#!/bin/bash
# Weekly rebuild + republish of the FTS and XTS lot-testing dashboards.
# Invoked by launchd (see edu.nd.lieberman.test-strip-weekly-update.plist) —
# not meant to be run interactively, though you can for a manual test:
#   bash run_weekly_update.sh
#
# Each dashboard gets its own `claude -p` invocation so a failure in one
# doesn't block the other. Logs go to log/<dashboard>_<timestamp>.log.

set -uo pipefail

REPO_DIR="$HOME/cPAD/test_strip_dashboard"
SCRIPT_DIR="$REPO_DIR/scripts/weekly_update"
LOG_DIR="$SCRIPT_DIR/log"
TS="$(date +%Y-%m-%d_%H%M%S)"

mkdir -p "$LOG_DIR"

echo "[$TS] starting weekly update" >> "$LOG_DIR/run_weekly_update.log"

cd "$REPO_DIR" || exit 1
git pull --ff-only origin main >> "$LOG_DIR/run_weekly_update.log" 2>&1

ALLOWED_TOOLS="Bash Read Write Artifact mcp__59170adc-5242-42d9-a35c-f748cfef1da1__download_file_content mcp__59170adc-5242-42d9-a35c-f748cfef1da1__get_file_metadata"

run_one () {
  local name="$1"
  local prompt_file="$2"
  local logfile="$LOG_DIR/${name}_${TS}.log"
  echo "[$TS] running $name, log: $logfile" >> "$LOG_DIR/run_weekly_update.log"
  claude -p "$(cat "$prompt_file")" \
    --allowedTools $ALLOWED_TOOLS \
    --output-format text \
    --add-dir "$REPO_DIR" \
    > "$logfile" 2>&1
  local status=$?
  echo "[$TS] $name exited with status $status" >> "$LOG_DIR/run_weekly_update.log"
  return $status
}

cd "$REPO_DIR" || exit 1
run_one "fts" "$SCRIPT_DIR/prompt_fts.md"
FTS_STATUS=$?

run_one "xts" "$SCRIPT_DIR/prompt_xts.md"
XTS_STATUS=$?

echo "[$TS] done. fts=$FTS_STATUS xts=$XTS_STATUS" >> "$LOG_DIR/run_weekly_update.log"

# keep the last 12 weeks of logs, prune older ones
find "$LOG_DIR" -name '*.log' -mtime +90 -delete

exit $(( FTS_STATUS != 0 || XTS_STATUS != 0 ))
