#!/usr/bin/env bash
# Repair Paperclip's local Codex callback URL without modifying public auth or Tailscale.
set -Eeuo pipefail
UNIT=te-paperclip-cos.service
API=http://127.0.0.1:3100
DIR=/etc/systemd/system/te-paperclip-cos.service.d
FILE="$DIR/90-local-agent-api.conf"
EXPECTED='[Service]
Environment="PAPERCLIP_API_URL=http://127.0.0.1:3100"'
[ "$(id -u)" = 0 ] || { echo ERROR=ROOT_REQUIRED; exit 1; }
systemctl is-active --quiet "$UNIT" || { echo ERROR=SERVICE_NOT_RUNNING; exit 1; }
curl -fsS --max-time 5 -o /dev/null "$API/health" || { echo ERROR=LOCAL_HEALTH_FAILED; exit 1; }
if [ -e "$FILE" ]; then
  [ "$(cat "$FILE")" = "$EXPECTED" ] || { echo ERROR=OVERRIDE_CONFLICT_NO_CHANGE; exit 1; }
  echo CONFIGURATION=ALREADY_PRESENT
fi
mkdir -p "$DIR"
CREATED=0
if [ ! -e "$FILE" ]; then
  TEMP="$(mktemp "$DIR/.90-local-api.XXXXXX")"
  printf '%s\n' "$EXPECTED" > "$TEMP"
  chmod 0644 "$TEMP"
  mv "$TEMP" "$FILE"
  CREATED=1
fi
rollback() {
  echo ERROR=LOCAL_API_REPAIR_FAILED
  if [ "$CREATED" = 1 ]; then
    rm -f "$FILE"
    systemctl daemon-reload
    systemctl restart "$UNIT" >/dev/null 2>&1 || true
    echo ROLLBACK=OVERRIDE_REMOVED
  else
    echo ROLLBACK=EXISTING_OVERRIDE_PRESERVED
  fi
  echo "SERVICE_STATE=$(systemctl is-active "$UNIT" 2>/dev/null || true)"
  exit 1
}
systemctl daemon-reload
systemctl restart "$UNIT" || rollback
READY=0
for n in $(seq 1 60); do
  if systemctl is-active --quiet "$UNIT" && curl -fsS --max-time 2 -o /dev/null "$API/health" 2>/dev/null; then
    READY=1
    break
  fi
  sleep 1
done
[ "$READY" = 1 ] || rollback
ENVINFO="$(systemctl show -p Environment --value "$UNIT")"
[[ "$ENVINFO" == *"PAPERCLIP_API_URL=$API"* ]] || rollback
# Systemd runs wrappers on some installations. Examine only the named unit's
# process and its descendants; never print any environment variables or secrets.
if ! python3 - "$(systemctl show -p MainPID --value "$UNIT")" "$API" <<'PY'
import os,sys
root=int(sys.argv[1])
expected=("PAPERCLIP_API_URL="+sys.argv[2]).encode()
if root<=0: sys.exit(1)
pids={root}
for _ in range(6):
    children=set()
    for p in pids:
        try:
            with open(f"/proc/{p}/task/{p}/children") as f:
                children.update(int(x) for x in f.read().split())
        except (OSError,ValueError): pass
    pids.update(children)
for p in pids:
    try:
        with open(f"/proc/{p}/environ","rb") as f:
            if expected in f.read().split(b"\0"):
                print("RUNTIME_PROCESS_API_URL=LOOPBACK_CONFIRMED")
                sys.exit(0)
    except OSError: pass
print("ERROR=RUNTIME_ENV_NOT_CONFIRMED")
sys.exit(1)
PY
then rollback; fi
echo RESULT=LOCAL_AGENT_API_CONFIGURED
echo LOCAL_AGENT_API="$API"
echo PUBLIC_TAILSCALE_BROWSER_URL=UNCHANGED
echo GITHUB_AND_CODEX_CREDENTIALS=UNCHANGED
echo "SERVICE_STATE=$(systemctl is-active "$UNIT")"
echo NEXT=Verify_a_new_agent_run_and_recover_the_previously_blocked_task
