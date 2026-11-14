#!/usr/bin/env bash
# Read-only summary of the ORCH Codex comparison; NO model requests.
set -euo pipefail
H=/home/tepilot
WORK="$H/comparisons/orch"
ORCH="$H/.local/node_modules/.bin/orch"
ENVPATH="/opt/te-ai-pilot/guard/bin:/opt/te-ai-pilot/node/bin:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin"
cd "$WORK"
TASK="$(cat "$WORK/.orchestry/pilot-task-id")"
echo "=== ORCH TASK SUMMARY ==="
runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY HOME="$H" CODEX_HOME="$H/.codex" PATH="$ENVPATH" "$ORCH" task show "$TASK"
echo "=== AGENT USAGE ==="
runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY HOME="$H" CODEX_HOME="$H/.codex" PATH="$ENVPATH" "$ORCH" --json agent list \
  | jq '[.[] | {agent:.name,adapter:.adapter,tokens:.stats.tokens_used,runs:.stats.total_runs,completed:.stats.tasks_completed}]'
echo "=== CURRENT TEST RESULT ==="
runuser -u tepilot -- python3 -m unittest discover -s tests -q
echo "=== SOURCE CHANGE SUMMARY ==="
runuser -u tepilot -- git status --short
runuser -u tepilot -- git diff --stat
echo "READ_ONLY_REPORT_COMPLETE"
