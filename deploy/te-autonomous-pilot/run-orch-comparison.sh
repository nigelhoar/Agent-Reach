#!/usr/bin/env bash
# Executes a SINGLE prepared ORCH task under a hard systemd runtime ceiling.
# Explicit model-using step: run only after checking credit auto-reload is OFF.
set -euo pipefail
H=/home/tepilot
WORK="$H/comparisons/orch"
BIN="$H/.local/node_modules/.bin"
GUARD=/opt/te-ai-pilot/guard/bin
PATH_ORCH="$GUARD:/opt/te-ai-pilot/node/bin:$BIN:/usr/local/bin:/usr/bin:/bin"
TASK_FILE="$WORK/.orchestry/pilot-task-id"
test "$(id -un)" = root
test -f "$TASK_FILE"
test -x "$GUARD/codex"
test "$(stat -c %U "$GUARD/codex")" = root
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT
TASK="$(cat "$TASK_FILE")"
case "$TASK" in tsk_*) ;; *) echo "Bad task ID"; exit 1;; esac

check_login() {
  runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
    HOME="$H" CODEX_HOME="$H/.codex" \
    PATH="$PATH_ORCH" "$BIN/codex" login status 2>&1
}
case "$(check_login)" in *"Logged in using ChatGPT"*) ;; *) echo "Login missing"; exit 1;; esac
echo "RUNNING_ORCH_TASK=$TASK"
echo "SANDBOX=WORKSPACE_WRITE"
echo "MAX_RUN_SECONDS=155"
set +e
systemd-run --quiet --wait --pipe --collect \
  --unit=te-orch-benchmark \
  --property=User=tepilot \
  --property=Group=tepilot \
  --property=WorkingDirectory="$WORK" \
  --property=RuntimeMaxSec=155 \
  --property=KillMode=control-group \
  --property=NoNewPrivileges=yes \
  --property=MemoryMax=1536M \
  --property=TasksMax=80 \
  --property=PrivateTmp=yes \
  --setenv="HOME=$H" \
  --setenv="CODEX_HOME=$H/.codex" \
  --setenv="PATH=$PATH_ORCH" \
  "$BIN/orch" run "$TASK"
RESULT=$?
set -e
echo "ORCH_EXIT=$RESULT"
echo "=== UNIT TESTS ==="
(cd "$WORK"; python3 -m unittest discover -s tests -v) || true
echo "=== DIFF STAT ==="
runuser -u tepilot -- git -C "$WORK" diff --stat
echo "=== ORCH TASK ==="
cd "$WORK"
runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
  HOME="$H" CODEX_HOME="$H/.codex" PATH="$PATH_ORCH" "$BIN/orch" task show "$TASK"
echo "=== AGENT USAGE ==="
runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
  HOME="$H" CODEX_HOME="$H/.codex" PATH="$PATH_ORCH" "$BIN/orch" --json agent list \
  | jq '[.[] | {agent:.name, adapter:.adapter, tokens:.stats.tokens_used, runs:.stats.total_runs}]'
echo "ORCH_BENCHMARK_REPORT_COMPLETE"
