#!/usr/bin/env bash
# First Paperclip Chief of Staff agent: use existing VM-hosted Codex login.
# Requires *Paperclip board-admin* browser approval, NOT OpenAI device login.
# No copying auth.json; never starts autonomous heartbeats or production work.
set -euo pipefail
SERVICE="te-cos-activate-existing-codex.service"
CMD=/usr/local/sbin/te-cos-activate-existing-codex-worker.sh
STATUS=/var/lib/te-cos-activate-existing-codex
NODE=/opt/te-paperclip/node/bin
CLI=/home/tepilot/.local/bin/paperclipai
API=http://127.0.0.1:3100
test "$(id -un)" = root
systemctl is-active --quiet te-paperclip-cos.service
curl -fsS --max-time 7 "$API/api/health" >/dev/null
test -x "$CLI"
test -f /home/tepilot/.codex/auth.json
install -d -m 0700 "$STATUS"
(
  cd /home/tepilot
  runuser -u tepilot -- env \
    -u OPENAI_API_KEY -u CODEX_API_KEY \
    HOME=/home/tepilot CODEX_HOME=/home/tepilot/.codex \
    PATH="$NODE:/home/tepilot/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
    /home/tepilot/.local/node_modules/.bin/codex login status
)
DNS="$(tailscale status --json | python3 -c 'import json,sys;print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))')"
[[ "$DNS" =~ ^[A-Za-z0-9._-]+\.ts\.net$ ]] || { echo "ERROR=TAILSCALE_DNS_NOT_READY"; exit 1; }
printf 'https://%s\n' "$DNS" >"$STATUS/public-url"
chmod 0600 "$STATUS/public-url"
cat >"$CMD" <<'WORKER'
#!/usr/bin/env bash
set -euo pipefail
STATUS=/var/lib/te-cos-activate-existing-codex
CLI=/home/tepilot/.local/bin/paperclipai
API=http://127.0.0.1:3100
export HOME=/root
export PAPERCLIP_HOME=/root/.paperclip
export PAPERCLIP_AUTH_STORE=/root/.paperclip/cos-board-auth.json
export PAPERCLIP_NO_BROWSER=1
export PATH=/opt/te-paperclip/node/bin:/usr/local/bin:/usr/bin:/bin
export PAPERCLIP_PUBLIC_URL="$(cat "$STATUS/public-url")"
umask 077
cleanup() {
  "$CLI" auth logout --api-base "$API" >/dev/null 2>&1 || true
}
trap cleanup EXIT
printf 'STATE=AWAITING_PAPERCLIP_CLI_APPROVAL\n' >"$STATUS/state"
# Paperclip's own board auth approval via private Tailscale HTTPS.
# The CLI stores its ephemeral board token in /root, inaccessible to
# tepilot/Codex agents. No OpenAI/ChatGPT device login occurs here.
"$CLI" auth login --api-base "$API" --instance-admin --no-browser >"$STATUS/board-login.log" 2>&1
printf 'STATE=PAPERCLIP_CLI_APPROVED\n' >"$STATUS/state"
COMPANIES="$("$CLI" company list --api-base "$API" --json)"
printf '%s\n' "$COMPANIES" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==1, "Expected exactly one owned Paperclip company"'
COMPANY_ID="$(printf '%s\n' "$COMPANIES" | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["id"])')"
AGENTS="$("$CLI" agent list --company-id "$COMPANY_ID" --api-base "$API" --json)"
# First agent is normally a provisional setup record with pauseReason=setup.
# Fail closed rather than guess which agent to update or create duplicates.
RESOLVE="$(printf '%s\n' "$AGENTS" | python3 -c '
import json,sys
a=json.load(sys.stdin)
assert isinstance(a,list), "Agent list must be array"
# Paperclip first-agent wizard initially assigns role="general", not "ceo".
# Only adopt the exact one-agent setup state; do not touch other agents.
active=[x for x in a if x.get("status")!="terminated"]
if not a:
    print("NEW")
elif len(active)==1 and len(a)==1:
    x=active[0]
    md=x.get("metadata") or {}
    if x.get("pauseReason")=="setup" and x.get("role") in ("general","ceo") and (md.get("setupAdapterPending") is True or x.get("name","").strip().lower() in ("chief of staff","chief of staff agent")):
        print("SETUP:"+x["id"]+":"+x.get("name","Chief of Staff"))
    elif x.get("role")=="ceo" and x.get("pauseReason")!="setup":
        print("EXISTS:"+x["id"])
    else:
        print("AGENT_INVENTORY="+json.dumps([{"name":x.get("name"),"role":x.get("role"),"status":x.get("status"),"pauseReason":x.get("pauseReason"),"setupPending":md.get("setupAdapterPending")}]),file=sys.stderr)
        raise SystemExit("Agent is not an identifiable first-agent setup; no changes made")
else:
    print("AGENT_INVENTORY="+json.dumps([{"name":x.get("name"),"role":x.get("role"),"status":x.get("status"),"pauseReason":x.get("pauseReason")} for x in a]),file=sys.stderr)
    raise SystemExit("Multiple agents or unsupported setup state; no changes made")
')"
if [[ "$RESOLVE" = EXISTS:* ]]; then
  printf 'STATE=AGENT_ALREADY_EXISTS\n' >"$STATUS/state"
  exit 0
fi
install -d -m 0700 -o tepilot -g tepilot /home/tepilot/paperclip-cos/workspaces/chief-of-staff
# Auth is inherited at execution from the existing external CODEX_HOME; only
# its directory path (not credential bytes) enters Paperclip's agent config.
PAYLOAD="$(python3 - "$RESOLVE" <<'PY'
import json,sys
stage=sys.argv[1]
d={
 "name":stage.split(":",2)[2] if stage.startswith("SETUP:") else "Chief of Staff",
 "role":"ceo",
 "title":"Chief of Staff",
 "adapterType":"codex_local",
 "runner":"legacy",
 "adapterConfig":{
   "cwd":"/home/tepilot/paperclip-cos/workspaces/chief-of-staff",
   "env":{"CODEX_HOME":"/home/tepilot/.codex"},
   "dangerouslyBypassApprovalsAndSandbox":False
 },
 "onboardingFirstAgent":True,
 "budgetMonthlyCents":0,
 "permissions":{"canCreateAgents":False, "canCreateSkills":False},
 "runtimeConfig":{"heartbeat":{"enabled":False, "intervalSec":86400,
    "wakeOnDemand":False, "skipTimerWhenNoActionableWork":True,
    "cooldownSec":10,"maxConcurrentRuns":1}}
}
if stage.startswith("SETUP:"): d["setupAgentId"]=stage.split(":",2)[1]
print(json.dumps(d,separators=(",",":")))
PY
)"
printf 'STATE=CONFIGURING_EXISTING_CODEX_AGENT\n' >"$STATUS/state"
# Agent-hire is the supported completion path for an onboarding setup agent.
# Use ordinary create only when there is genuinely no agent yet.
if [[ "$RESOLVE" = NEW ]]; then
  RESULT="$("$CLI" agent create --company-id "$COMPANY_ID" --runner legacy --api-base "$API" --payload-json "$PAYLOAD" --json)"
else
  RESULT="$("$CLI" agent hire --company-id "$COMPANY_ID" --runner legacy --api-base "$API" --payload-json "$PAYLOAD" --json)"
fi
printf '%s\n' "$RESULT" | python3 -c '
import json,sys
r=json.load(sys.stdin)
if isinstance(r,dict):
    agent=r.get("agent",r)
    if isinstance(agent,dict):
        print("CHIEF_OF_STAFF_ID="+str(agent.get("id","UNKNOWN")))
    if r.get("approval"): print("AGENT_APPROVAL=PENDING_REVIEW")
'
printf 'STATE=CHIEF_OF_STAFF_CONFIGURED\n' >"$STATUS/state"
echo "AGENT_AUTH=EXISTING_CODEX_HOME"
echo "OPENAI_DEVICE_CODE_LOGIN=NOT_REQUIRED"
echo "HEARTBEAT=DISABLED"
WORKER
chmod 0700 "$CMD"
cat >"/etc/systemd/system/$SERVICE" <<UNIT
[Unit]
Description=One-shot Paperclip CEO activation using existing Codex subscription
After=network-online.target te-paperclip-cos.service tailscaled.service
Requires=te-paperclip-cos.service
[Service]
Type=oneshot
ExecStart=$CMD
TimeoutStartSec=1200
StandardOutput=append:$STATUS/activation.log
StandardError=append:$STATUS/activation.log
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
touch "$STATUS/board-login.log" "$STATUS/activation.log"
chmod 0600 "$STATUS/board-login.log" "$STATUS/activation.log"
if [ -f "$STATUS/state" ] && grep -q '^STATE=CHIEF_OF_STAFF_CONFIGURED' "$STATUS/state"; then
  cat "$STATUS/state"
  exit 0
fi
if ! systemctl is-active --quiet "$SERVICE"; then
  systemctl reset-failed "$SERVICE" >/dev/null 2>&1 || true
  systemctl start --no-block "$SERVICE"
fi
echo "PAPERCLIP_VM_CLI_AUTH=REQUESTED"
for n in $(seq 1 40); do
  APPROVAL="$(grep -Eo 'https://[^[:space:]]+/cli-auth/[^[:space:]]+' "$STATUS/board-login.log" 2>/dev/null | head -n 1 || true)"
  if [ -z "$APPROVAL" ]; then
    APPROVAL="$(grep -Eo 'https://[^[:space:]]+' "$STATUS/board-login.log" 2>/dev/null | grep -E '/cli-auth|/auth/' | head -n 1 || true)"
  fi
  if [ -n "$APPROVAL" ]; then
    echo "OPEN_IN_PHONE_TO_APPROVE_PAPERCLIP_CLI=$APPROVAL"
    break
  fi
  sleep 1
done
cat "$STATUS/state" 2>/dev/null || true
if [ -z "$(grep -Eo 'https://[^[:space:]]+' "$STATUS/board-login.log" 2>/dev/null | head -n 1 || true)" ]; then
  echo "CLI_APPROVAL_URL_UNAVAILABLE=See service logs; do not enter an OpenAI device code"
fi
echo "NEXT=Approve the Paperclip CLI access request in your Tailscale browser. VM will then use existing Codex login to complete the first agent."
echo "IMPORTANT=Do not post or forward the approval link or credentials."
