#!/usr/bin/env bash
# Short, private Tailscale link for a Paperclip CLI approval.
# Resumes a running challenge; safely renews it if the worker has exited.
# Never prints tokens, changes Paperclip, or enables Tailscale Funnel.
set -euo pipefail
test "$(id -un)" = root
D=/var/lib/te-cos-activate-existing-codex
test -f "$D/board-login.log"
test -f "$D/state"
systemctl is-active --quiet te-paperclip-cos.service
# The CLI approval worker is a systemd Type=oneshot unit. While it waits
# for browser approval its normal ActiveState is *activating*, not active.
# is-active --quiet wrongly rejects this and caused the previous failure.
# Check whether its actual MainPID is alive instead, preserving its
# existing approval challenge rather than unnecessarily minting a new one.
WORKER=te-cos-activate-existing-codex.service
STATE="$(cat "$D/state")"
if [ "$STATE" = 'STATE=CHIEF_OF_STAFF_CONFIGURED' ]; then
  echo 'STATE=CHIEF_OF_STAFF_CONFIGURED'
  echo 'NEXT=Refresh Paperclip; no further CLI approval is needed.'
  exit 0
fi
PID="$(systemctl show -p MainPID --value "$WORKER" 2>/dev/null || true)"
if [[ "$PID" =~ ^[0-9]+$ ]] && (( PID > 0 )) && kill -0 "$PID" 2>/dev/null; then
  echo 'PAPERCLIP_APPROVAL_WORKER=RUNNING'
else
  echo 'PAPERCLIP_APPROVAL_WORKER=RESTARTING'
  # An expired or failed approval invalidates its old browser URL. The worker
  # writes a fresh challenge and keeps its own board token private.
  : > "$D/board-login.log"
  systemctl reset-failed "$WORKER" >/dev/null 2>&1 || true
  systemctl start --no-block "$WORKER"
  # Wait for the new challenge and its pending state; NEVER echo its token.
  READY=0
  for n in $(seq 1 30); do
    PID="$(systemctl show -p MainPID --value "$WORKER" 2>/dev/null || true)"
    if grep -qx 'STATE=AWAITING_PAPERCLIP_CLI_APPROVAL' "$D/state" \
      && grep -q 'Open this URL in your browser to approve CLI access:' "$D/board-login.log" \
      && [[ "$PID" =~ ^[0-9]+$ ]] && (( PID > 0 )) && kill -0 "$PID" 2>/dev/null; then
      READY=1
      break
    fi
    sleep 1
  done
  if [ "$READY" != 1 ]; then
    echo 'ERROR=NEW_PAPERCLIP_CLI_APPROVAL_NOT_READY'
    echo "WORKER_STATE=$(systemctl show -p ActiveState --value "$WORKER")"
    # No raw logs here: logs contain a secret capability URL.
    exit 1
  fi
fi
if ! grep -qx 'STATE=AWAITING_PAPERCLIP_CLI_APPROVAL' "$D/state"; then
  echo "STATE=$(cat "$D/state")"
  echo 'ERROR=NO_PENDING_APPROVAL_TO_SHORTEN'
  exit 1
fi
FQDN="$(tailscale status --json | python3 -c 'import json,sys;print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))')"
[[ "$FQDN" =~ ^[A-Za-z0-9._-]+\.ts\.net$ ]] || {
  echo 'ERROR=TAILSCALE_DNS_NOT_READY'
  exit 1
}
# Only add a second private route if the existing Paperclip root route is intact.
BEFORE="$(mktemp)"
AFTER="$(mktemp)"
trap 'rm -f "$BEFORE" "$AFTER"' EXIT
tailscale serve status --json >"$BEFORE"
python3 - "$BEFORE" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1]))
handlers=[v.get("Handlers",{}) for v in (cfg.get("Web") or {}).values()]
if not any(any(k.rstrip("/") in ("", "/") and (h.get("Proxy") or "").rstrip("/") == "http://127.0.0.1:3100" for k,h in hs.items()) for hs in handlers):
  raise SystemExit("ERROR=PAPERCLIP_ROOT_ROUTE_NOT_VERIFIED")
for hs in handlers:
  if "/go" in hs and (hs["/go"].get("Proxy") or "").rstrip("/") != "http://127.0.0.1:3115":
    raise SystemExit("ERROR=PRIVATE_GO_PATH_ALREADY_IN_USE")
if cfg.get("AllowFunnel"):
  raise SystemExit("ERROR=UNEXPECTED_FUNNEL_CONFIG")
PY
# Local redirector only reads the existing pending challenge; never stores a second token.
install -d -m 0755 /usr/local/libexec
cat >/usr/local/libexec/te-paperclip-cli-approve-shortlink.py <<'PY'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
import json,re,subprocess

D=Path("/var/lib/te-cos-activate-existing-codex")
def redirect_target():
    status=(D/"state").read_text().strip()
    if status!="STATE=AWAITING_PAPERCLIP_CLI_APPROVAL":
        return None
    log=(D/"board-login.log").read_text()
    match=re.search(r"Open this URL in your browser to approve CLI access:\s*\n(https://[^\s]+)",log)
    if not match: return None
    url=match.group(1).strip()
    parts=urlsplit(url)
    info=json.loads(subprocess.check_output(["/usr/bin/tailscale","status","--json"],text=True))
    host=info["Self"]["DNSName"].rstrip(".")
    # Never turn this shortlink into an open redirect or an external URL.
    if parts.scheme!="https" or parts.hostname!=host or parts.port is not None or not parts.path.startswith("/cli-auth/"):
        return None
    if not parse_qs(parts.query).get("token"): return None
    return url

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/","/go","/go/"):
            self.send_error(404)
            return
        url=redirect_target()
        if not url:
            msg=b"No pending Paperclip CLI approval. Return to the Paperclip dashboard."
            self.send_response(410)
            self.send_header("Content-Type","text/plain; charset=utf-8")
            self.send_header("Cache-Control","no-store")
            self.send_header("Content-Length",str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
            return
        self.send_response(303)
        self.send_header("Location",url)
        self.send_header("Cache-Control","no-store, private")
        self.send_header("Referrer-Policy","no-referrer")
        self.send_header("Content-Length","0")
        self.end_headers()
    def log_message(self,*args):
        pass

ThreadingHTTPServer(("127.0.0.1",3115), Handler).serve_forever()
PY
chmod 0755 /usr/local/libexec/te-paperclip-cli-approve-shortlink.py
cat >/etc/systemd/system/te-paperclip-cli-approve-shortlink.service <<'UNIT'
[Unit]
Description=Private shortlink for pending Paperclip CLI approval
After=network-online.target tailscaled.service
Requires=tailscaled.service
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/libexec/te-paperclip-cli-approve-shortlink.py
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
UMask=0077
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable te-paperclip-cli-approve-shortlink.service >/dev/null
# Type=simple is considered started before Python binds its listener. Wait
# for readiness instead of treating an immediate ECONNREFUSED as fatal.
if ! systemctl is-active --quiet te-paperclip-cli-approve-shortlink.service; then
  systemctl reset-failed te-paperclip-cli-approve-shortlink.service >/dev/null 2>&1 || true
  systemctl start te-paperclip-cli-approve-shortlink.service
fi
READY=0
for n in $(seq 1 40); do
  HTTP="$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' 'http://127.0.0.1:3115/' 2>/dev/null || true)"
  if [ "$HTTP" = "303" ]; then READY=1; break; fi
  if [ "$HTTP" = "410" ]; then
    echo 'ERROR=PAPERCLIP_APPROVAL_CHALLENGE_NOT_AVAILABLE'
    exit 1
  fi
  if ! systemctl is-active --quiet te-paperclip-cli-approve-shortlink.service; then
    echo 'ERROR=SHORTLINK_SERVICE_FAILED'
    journalctl -u te-paperclip-cli-approve-shortlink.service -n 15 --no-pager 2>/dev/null || true
    exit 1
  fi
  sleep 0.5
done
if [ "$READY" != 1 ]; then
  echo 'ERROR=SHORTLINK_SERVICE_NOT_LISTENING'
  systemctl show te-paperclip-cli-approve-shortlink.service -p ActiveState -p SubState -p ExecMainStatus --no-pager || true
  journalctl -u te-paperclip-cli-approve-shortlink.service -n 15 --no-pager 2>/dev/null || true
  exit 1
fi
echo 'SHORTLINK_LOCAL_LISTENER=READY'
# Add only /go to existing Tailnet HTTPS Serve; preserves Paperclip '/' and leaves Funnel off.
tailscale serve --yes --bg --https=443 --set-path=/go http://127.0.0.1:3115 >/dev/null
tailscale serve status --json >"$AFTER"
python3 - "$AFTER" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1]))
h=[v.get("Handlers",{}) for v in (cfg.get("Web") or {}).values()]
if not any(v.get("/go",{}).get("Proxy","").rstrip("/") == "http://127.0.0.1:3115" for v in h):
    raise SystemExit("ERROR=SHORTLINK_ROUTE_NOT_VERIFIED")
if not any(v.get("/",{}).get("Proxy","").rstrip("/") == "http://127.0.0.1:3100" for v in h):
    raise SystemExit("ERROR=PAPERCLIP_ROUTE_NOT_PRESERVED")
if cfg.get("AllowFunnel"):
    raise SystemExit("ERROR=UNEXPECTED_FUNNEL_CONFIG")
PY
echo "SHORT_PRIVATE_APPROVAL_LINK=https://$FQDN/go"
echo "PHONE_INSTRUCTION=In the existing Paperclip browser tab, replace the path after .ts.net with /go. Tap Approve."
echo "RANDOM_TOKEN_ENTRY=NOT_REQUIRED"
echo "OPENAI_DEVICE_CODE_LOGIN=NOT_REQUIRED"
echo "FUNNEL=DISABLED"
echo "PAPERCLIP_ROOT=UNCHANGED"
