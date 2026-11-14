#!/usr/bin/env bash
# Prepare a fresh Agent of Empires comparison checkout and a STOPPED session.
# The script MUST NOT launch Codex or submit an AI prompt.
set -euo pipefail
H=/home/tepilot
BASE="$H/benchmark"
WORK="$H/comparisons/aoe"
AOE="$H/.local/bin/aoe"
CODEX="$H/.local/node_modules/.bin/codex"
PATH_AOE="/opt/te-ai-pilot/node/bin:$H/.local/bin:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin"
TITLE="te-aoe-synthetic"
test "$(id -un)" = root
test -x "$AOE" && test -x "$CODEX"
test -d "$BASE/.git"
test ! -e "$WORK" || { echo "AoE comparison already exists, refusing overwrite"; exit 1; }
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT
STATUS="$(runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY HOME="$H" CODEX_HOME="$H/.codex" PATH="$PATH_AOE" "$CODEX" login status 2>&1)"
case "$STATUS" in *"Logged in using ChatGPT"*) ;; *) echo "ChatGPT subscription login absent"; exit 1;; esac
runuser -u tepilot -- git clone -q --no-local "$BASE" "$WORK"
runuser -u tepilot -- git -C "$WORK" diff --quiet
set +e
runuser -u tepilot -- env HOME="$H" bash -c "cd '$WORK'; python3 -m unittest discover -s tests -q" >/dev/null 2>&1
BASE_RC=$?
set -e
[ "$BASE_RC" -ne 0 ] || { echo "Original benchmark must fail"; exit 1; }
# AoE add creates and records the session but DOES NOT start it without --launch.
# Explicit CLI arguments restrict Codex to its writable project folder.
runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY HOME="$H" CODEX_HOME="$H/.codex" PATH="$PATH_AOE" \
  "$AOE" add --cmd codex --title "$TITLE" \
  --extra-args "--sandbox workspace-write --ask-for-approval never" --skip-on-create "$WORK"
echo "AOE_SESSION_PREPARED=$TITLE"
echo "AOE_SESSION_LAUNCHED=NO"
echo "MODEL_CALLS=ZERO"
