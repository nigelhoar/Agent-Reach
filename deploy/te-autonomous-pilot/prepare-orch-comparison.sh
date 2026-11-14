#!/usr/bin/env bash
# PREPARE a single bounded ORCH comparison. Does not invoke an AI model.
set -euo pipefail
H=/home/tepilot
BASE="$H/benchmark"
WORK="$H/comparisons/orch"
BIN="$H/.local/node_modules/.bin"
GUARD=/opt/te-ai-pilot/guard/bin
PATH_ORCH="$GUARD:/opt/te-ai-pilot/node/bin:$BIN:/usr/local/bin:/usr/bin:/bin"
test "$(id -un)" = root
test -d "$BASE/.git"
test -x "$BIN/orch"
test -x "$BIN/codex"
test ! -e "$WORK" || { echo "Already prepared; refusing to overwrite checkout"; exit 1; }
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT

STATUS="$(runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY HOME="$H" CODEX_HOME="$H/.codex" PATH="$PATH_ORCH" "$BIN/codex" login status 2>&1)"
case "$STATUS" in
  *"Logged in using ChatGPT"*) echo "SUBSCRIPTION_LOGIN=OK";;
  *) echo "Subscription login unavailable"; exit 1;;
esac

install -d -m 0755 "$GUARD"
curl -fsSL --retry 3 \
  https://raw.githubusercontent.com/nigelhoar/Agent-Reach/d2ebbc16192660ddc6516aff2f5b72345c11922a/deploy/te-autonomous-pilot/guarded-codex-for-orch.sh \
  -o "$GUARD/codex"
chmod 0755 "$GUARD/codex"
chown root:root "$GUARD/codex"
bash -n "$GUARD/codex"
grep -q 'sandbox=workspace-write' "$GUARD/codex"
install -d -o tepilot -g tepilot -m 0700 "$H/comparisons"
runuser -u tepilot -- git clone -q --no-local "$BASE" "$WORK"
runuser -u tepilot -- git -C "$WORK" diff --quiet
cd "$WORK"

# Expected baseline failure: the original committed version has a duplicate bug.
set +e
runuser -u tepilot -- env HOME="$H" python3 -m unittest discover -s tests -q >/dev/null 2>&1
BASE_EXIT=$?
set -e
[ "$BASE_EXIT" -ne 0 ] || { echo "Unexpectedly clean baseline"; exit 1; }

run_orch() {
  runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
    HOME="$H" CODEX_HOME="$H/.codex" PATH="$PATH_ORCH" "$BIN/orch" "$@"
}
run_orch init --name te-synthetic-orch --adapter codex
AGENT="$(run_orch --quiet agent add te-pilot-coder --adapter codex \
  --role "Synthetic Python test repair only; no network or external repositories" \
  --max-turns 1 --timeout 120000 --workspace-mode shared --approval-policy auto)"
case "$AGENT" in agt_*) ;; *) echo "Cannot confirm agent ID: $AGENT"; exit 1;; esac
DESC="Fix unique_tasks to remove duplicates while preserving order, including lists and other unhashable items. Add an edge-case unit test, run python3 -m unittest discover -s tests -v. Modify only task_queue.py and tests/test_task_queue.py. Do not install packages, access other directories, call the network, or deploy."
TASK="$(run_orch --quiet task add "Repair unique_tasks in synthetic project" \
  -d "$DESC" -p 1 --max-attempts 1 --workspace-mode shared --assignee "$AGENT")"
case "$TASK" in tsk_*) ;; *) echo "Cannot confirm task ID: $TASK"; exit 1;; esac
printf '%s\n' "$TASK" > "$WORK/.orchestry/pilot-task-id"
chown tepilot:tepilot "$WORK/.orchestry/pilot-task-id"
echo "ORCH_PREPARED=YES"
echo "TASK_ID=$TASK"
echo "MAX_ATTEMPTS=1"
echo "CODING_MODEL_CALLS=ZERO"
