#!/usr/bin/env bash
# One controlled AoE retry after Codex stopped on hook review (no model turn).
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
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT
run_as_pilot() {
  runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
    HOME="$H" CODEX_HOME="$H/.codex" PATH="$RUNPATH" "$@"
}
case "$(run_as_pilot "$CODEX" login status 2>&1)" in
  *"Logged in using ChatGPT"*) ;;
  *) echo "ChatGPT subscription login missing"; exit 1;;
esac
# Do not permit a repeated AI session after a previously successful attempt.
run_as_pilot git -C "$WORK" diff --quiet
run_as_pilot git -C "$WORK" diff --cached --quiet
set +e
run_as_pilot bash -c 'cd /home/tepilot/comparisons/aoe && python3 -m unittest discover -s tests -q' >/dev/null 2>&1
BASE_TEST=$?
set -e
test "$BASE_TEST" -ne 0 || { echo "Baseline already fixed; abort duplicate run"; exit 1; }
test -f "$STAMP" && test -f "$RUNLOG"
test "$(stat -c %U "$STAMP")" = tepilot
grep -Fq "Hooks need review" "$RUNLOG" || { echo "Last run not provably hook-blocked; abort"; exit 1; }
test ! -e "$STAMP.blocked-by-hooks" || { echo "Previous retry exists; abort"; exit 1; }
mv "$STAMP" "$STAMP.blocked-by-hooks"
touch "$STAMP"
chown tepilot:tepilot "$STAMP"
# Independent systemd watchdog survives a broken/disconnected Azure Run Command.
systemd-run --quiet --unit="$WATCHDOG" --on-active=180s \
  --property=User=tepilot --property=Group=tepilot \
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

# AoE approved its hook installation; Codex separately prompts to trust them.
# Codex's interface explicitly offers "Esc skip", without trusting or executing hooks.
ID8="${SID:0:8}"
mapfile -t SESSIONS < <(run_as_pilot tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E "^aoe_.*_${ID8}$" || true)
if [ "${#SESSIONS[@]}" -ne 1 ]; then
  echo "Unable to identify exactly one pilot tmux session; refusing input"
  exit 1
fi
TMUX_TARGET="=${SESSIONS[0]}"
echo "SYNTHETIC_TMUX_SESSION=VERIFIED"
READY=0
REVIEW_SEEN=0
for _ in $(seq 1 30); do
  SCREEN="$(run_as_pilot "$AOE" -p main session capture --strip-ansi --lines 40 "$SID" 2>/dev/null || true)"
  if [[ "$SCREEN" == *"Hooks need review"* ]]; then
    if [ "$REVIEW_SEEN" -eq 0 ]; then
      echo "CODEX_HOOK_REVIEW_DETECTED=YES"
      run_as_pilot tmux send-keys -t "$TMUX_TARGET" 3
      echo "CODEX_HOOKS_TRUST=SKIPPED"
      REVIEW_SEEN=1
    fi
  elif [[ "$SCREEN" == *"›"* ]]; then
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  echo "Codex is not at its normal prompt; no task sent"
  run_as_pilot "$AOE" -p main session capture --strip-ansi --lines 55 "$SID" || true
  exit 1
fi
echo "CODEX_INTERACTIVE_READY=YES"

PROMPT="In this synthetic Python project only: fix unique_tasks to remove duplicates while preserving first occurrence, including unhashable lists and dictionaries. Add an edge-case unit test and run python3 -m unittest discover -s tests -v. Do not install packages, use networking, access other directories, or deploy anything. Finish with a concise summary."
echo "SENDING_ONE_SYNTHETIC_TASK=YES"
run_as_pilot "$AOE" -p main send --no-revive "$SID" "$PROMPT"

# Check actual code and tests, not hook-based activity status (we skipped hooks).
DEADLINE=$((SECONDS + 105))
NEW_TEST_PASS=NO
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  if run_as_pilot bash -c 'cd /home/tepilot/comparisons/aoe && python3 -m unittest discover -s tests -q' >/dev/null 2>&1; then
    if ! run_as_pilot git -C "$WORK" diff --quiet -- tests/test_task_queue.py; then
      NEW_TEST_PASS=YES
      break
    fi
  fi
  sleep 3
done
echo "NEW_TEST_AND_PASSING_SUITE=$NEW_TEST_PASS"
if [ "$NEW_TEST_PASS" = YES ]; then sleep 4; fi
echo "=== TERMINAL CAPTURE ==="
run_as_pilot "$AOE" -p main session capture --strip-ansi --lines 35 "$SID" | tee "$RUNLOG" || true
chown tepilot:tepilot "$RUNLOG"
cleanup
trap - EXIT
echo "AGENT_SESSION_STOPPED=YES"
echo "=== FINAL UNIT TESTS ==="
set +e
run_as_pilot bash -c 'cd /home/tepilot/comparisons/aoe && python3 -m unittest discover -s tests -v'
TEST_EXIT=$?
set -e
echo "TEST_EXIT=$TEST_EXIT"
echo "=== SOURCE CHANGES ==="
run_as_pilot git -C "$WORK" diff --stat
run_as_pilot git -C "$WORK" status --short
echo "AOE_COMPARISON_COMPLETE"
