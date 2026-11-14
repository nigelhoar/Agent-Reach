#!/usr/bin/env bash
# Deliberate first Codex execution on the synthetic benchmark.
# Run only after confirming subscription login and disabled credit auto-reload.
set -euo pipefail
HOME_DIR=/home/tepilot
CODEX="$HOME_DIR/.local/node_modules/.bin/codex"
NODE=/opt/te-ai-pilot/node/bin
test "$(id -un)" = "root" || { echo "Use Azure VM RunCommand as root"; exit 1; }
systemctl is-active --quiet te-ai-pilot-block-imds.service || { echo "IMDS block absent"; exit 1; }
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT
test -x "$CODEX" || { echo "No Codex binary"; exit 1; }
STATUS="$(runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
  HOME="$HOME_DIR" CODEX_HOME="$HOME_DIR/.codex" \
  PATH="$NODE:$HOME_DIR/.local/node_modules/.bin:/usr/bin:/bin" \
  "$CODEX" login status 2>&1)" || { echo "Codex subscription login missing"; exit 1; }
echo "$STATUS"
echo "$STATUS" | grep -qi 'chatgpt' || { echo "Not explicitly logged into ChatGPT; refusing to run"; exit 1; }

cd "$HOME_DIR/benchmark"
test -f AGENTS.md && test -f task_queue.py
test -d .git
install -d -o tepilot -g tepilot -m 0700 "$HOME_DIR/results"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$HOME_DIR/results/codex-$RUN_ID.jsonl"
PROMPT="In this synthetic repository only: implement the unique_tasks function according to its docstring, add an edge-case unit test, run python3 -m unittest discover -s tests -v, and summarize changes. Do not install packages, make network requests, access other directories or credentials, or deploy anything."
echo "STARTING: one Codex session, maximum 600 seconds, workspace-write sandbox."
set +e
runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
  HOME="$HOME_DIR" CODEX_HOME="$HOME_DIR/.codex" \
  PATH="$NODE:$HOME_DIR/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
  timeout --signal=TERM --kill-after=15s 600s \
  "$CODEX" exec --json --sandbox workspace-write --config 'approval_policy="never"' \
  "$PROMPT" >"$LOG" 2>&1
RESULT=$?
set -e
chown tepilot:tepilot "$LOG"
echo "CODEX_EXIT=$RESULT"
echo "RESULT_LOG=$LOG"
echo "=== CURRENT TESTS ==="
python3 -m unittest discover -s tests -v || true
echo "=== CHANGED FILES ==="
git status --short
echo "=== CODEX EVENT SUMMARY ==="
python3 - "$LOG" <<'PY'
import sys,json,collections
c=collections.Counter()
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    try:
        obj=json.loads(line)
        c[str(obj.get("type","unknown"))]+=1
    except Exception:
        pass
print(dict(c))
PY
exit 0
