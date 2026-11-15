#!/usr/bin/env bash
# Short, private Tailscale link for an already-pending Paperclip CLI approval.
# Does not regenerate a challenge, print tokens, modify Paperclip, or expose Funnel.
set -euo pipefail
test "$(id -un)" = root
D=/var/lib/te-cos-activate-existing-codex
test -f "$D/board-login.log"
test -f "$D/state"
grep -qx 'STATE=AWAITING_PAPERCLIP_CLI_APPROVAL' "$D/state" || {
  echo "No pending CLI approval: $(cat "$D/state")"
  exit 0
}
systemctl is-active --quiet te-cos-activate-existing-codex.service || {
  echo 'ERROR=CLI_APPROVAL_WORKER_IS_NOT_RUNNING'
  exit 1
}
systemctl is-active --quiet te-paperclip-cos.service
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
systemctl enable --now te-paperclip-cli-approve-shortlink.service >/dev/null
systemctl is-active --quiet te-paperclip-cli-approve-shortlink.service
curl -fsS --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:3115/" | grep -qx '303'
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
