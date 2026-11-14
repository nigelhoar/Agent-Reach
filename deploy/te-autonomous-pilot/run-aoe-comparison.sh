#!/usr/bin/env bash
# Agent of Empires v1.23.0 synthetic Codex benchmark.
# ONE model-using task, with a separate wall-clock stop timer.
set -euo pipefail
SID=6aa03862844a4416
H=/home/tepilot
WORK="$H/comparisons/aoe"
AOE="$H/.local/bin/aoe"
CODEX="$H/.local/node_modules/.bin/codex"
RUNPATH="/opt/te-ai-pilot/node/bin:$H/.local/bin:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin"
WATCHDOG=te-aoe-pilot-watchdog
STAMP="$WORK/.te-aoe-pilot-started"
RUNLOG="$H/results/aoe-synthetic-output.txt"

test "$(id -un)" = root
test -x "$AOE" && test -x "$CODEX"
test -d "$WORK/.git"
test "$(stat -c %U "$WORK")" = tepilot
test ! -e "$STAMP" || { echo "This task was already launched. Refusing duplicate subscription usage."; exit 1; }
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT

run_as_pilot() {
  runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
    HOME="$H" CODEX_HOME="$H/.codex" PATH="$RUNPATH" "$@"
}
STATUS="$(run_as_pilot "$CODEX" login status 2>&1)"
case "$STATUS" in *"Logged in using ChatGPT"*) ;; *) echo "Subscription authentication not available"; exit 1;; esac

# Original synthetic source must still have the intentionally failing test.
run_as_pilot git -C "$WORK" diff --quiet
run_as_pilot git -C "$WORK" diff --cached --quiet
set +e
(cd "$WORK"; python3 -m unittest discover -s tests -q >/dev/null 2>&1)
INITIAL_TEST=$?
set -e
test "$INITIAL_TEST" -ne 0 || { echo "Baseline tests already pass; stop."; exit 1; }
mkdir -p "$H/results"
touch "$STAMP"
chown tepilot:tepilot "$STAMP"

# Separate systemd timer remains active even if this VM RunCommand disconnects.
systemd-run --quiet --unit="$WATCHDOG" --on-active=180s \
  --property=User=tepilot \
  --property=Group=tepilot \
  --setenv="HOME=$H" --setenv="CODEX_HOME=$H/.codex" \
  --setenv="PATH=$RUNPATH" \
  "$AOE" -p main session stop "$SID"
echo "INDEPENDENT_STOP_WATCHDOG=ARMED_180_SECONDS"

cleanup() {
  run_as_pilot "$AOE" -p main session stop "$SID" >/dev/null 2>&1 || true
  systemctl stop "$WATCHDOG.timer" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "STARTING_AGENT_OF_EMPIRES_SESSION=$SID"
run_as_pilot "$AOE" -p main session start "$SID"
# Wait for the native CLI to reach its input prompt, not just for tmux startup.
set +e
run_as_pilot "$AOE" -p main session wait --until idle --timeout 35000 "$SID" >/dev/null
READY=$?
set -e
if [ "$READY" -ne 0 ]; then
  echo "WARNING: native CLI did not report idle; capturing initial terminal"
  run_as_pilot "$AOE" -p main session capture --strip-ansi --lines 25 "$SID" || true
  exit 1
fi
echo "CODEX_INTERACTIVE_READY=YES"

PROMPT="In this synthetic Python project only: fix the unique_tasks function to remove duplicates while preserving first occurrence, including duplicate unhashable lists and dictionaries. Add an edge-case unit test and run python3 -m unittest discover -s tests -v. Do not install packages, use networking, access other directories, or deploy anything. Finish with a concise summary."

echo "SENDING_ONE_SYNTHETIC_TASK=YES"
run_as_pilot "$AOE" -p main send --no-revive "$SID" "$PROMPT"

set +e
run_as_pilot "$AOE" -p main session wait --until idle --until waiting --until error --timeout 125000 "$SID"
WAIT_CODE=$?
set -e
echo "AGENT_WAIT_EXIT=$WAIT_CODE"
echo "=== CAPTURE LAST 80 TERMINAL LINES ==="
run_as_pilot "$AOE" -p main session capture --strip-ansi --lines 80 "$SID" | tee "$RUNLOG" || true
chown tepilot:tepilot "$RUNLOG"

# Must stop the interactive agent; retaining the AoE session record is okay.
cleanup
trap - EXIT
echo "AGENT_SESSION_STOPPED=YES"

echo "=== FINAL TEST RESULT ==="
set +e
(cd "$WORK"; python3 -m unittest discover -s tests -v)
TEST_RESULT=$?
set -e
echo "TEST_EXIT=$TEST_RESULT"
echo "=== CHANGES ==="
run_as_pilot git -C "$WORK" diff --stat
run_as_pilot git -C "$WORK" status --short
echo "AOE_COMPARISON_COMPLETE"
