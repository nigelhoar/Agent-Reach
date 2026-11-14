#!/usr/bin/env bash
# TE Chief of Staff private Android access. Run as root with Azure VM RunCommand.
# Tailscale Serve, NOT Funnel. No public IP, DNS, Cloudflare or NSG changes.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
echo "=== PAPERCLIP AND VM PRECHECKS ==="
test "$(id -un)" = "root"
systemctl is-active --quiet te-paperclip-cos.service
curl -fsS --max-time 7 http://127.0.0.1:3100/api/health >/dev/null
python3 - <<'PY'
import json
p="/home/tepilot/paperclip-cos/instances/default/config.json"
s=json.load(open(p))["server"]
assert s["deploymentMode"] == "authenticated" and s["exposure"] == "private", "Paperclip must require authentication"
assert s["bind"] == "loopback" and s["host"] == "127.0.0.1", "Paperclip must be loopback-only"
print("PAPERCLIP_AUTHENTICATED_PRIVATE=VERIFIED")
PY
echo "=== INSTALL OFFICIAL TAILSCALE PACKAGE ==="
. /etc/os-release
test "$ID" = "ubuntu" && test "$VERSION_CODENAME" = "jammy" || { echo "Unsupported Ubuntu release; no changes made"; exit 1; }
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg python3
install -d -m 0755 /usr/share/keyrings
curl -fsSL --retry 3 https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL --retry 3 https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
apt-get update -qq
apt-get install -y -qq tailscale
systemctl enable --now tailscaled
/usr/bin/tailscale version | head -n 2

install -d -m 0700 /var/lib/te-cos-tailnet
touch /var/lib/te-cos-tailnet/login.log /var/lib/te-cos-tailnet/serve-attempt.log
chmod 0600 /var/lib/te-cos-tailnet/login.log /var/lib/te-cos-tailnet/serve-attempt.log

echo "=== INSTALL AUTOMATIC HTTPS FINALIZER ==="
cat >/usr/local/sbin/te-cos-tailnet-finalize.sh <<'FINISH'
#!/usr/bin/env bash
set -euo pipefail
DIR=/var/lib/te-cos-tailnet
CONFIG=/home/tepilot/paperclip-cos/instances/default/config.json
STATUS="$DIR/status.txt"
install -d -m 0700 "$DIR"
if ! /usr/bin/tailscale status --json 2>/dev/null | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("BackendState")=="Running" else 1)'; then
  printf 'STATE=AWAITING_TAILSCALE_LOGIN\n' >"$STATUS"
  chmod 0600 "$STATUS"
  exit 0
fi
DNS="$(/usr/bin/tailscale status --json | python3 -c 'import sys,json; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))')"
if ! [[ "$DNS" =~ ^[a-zA-Z0-9._-]+\.ts\.net$ ]]; then
  printf 'STATE=AWAITING_MAGICDNS\n' >"$STATUS"
  chmod 0600 "$STATUS"
  exit 0
fi
URL="https://$DNS"
# Set authenticated HTTPS origin without changing Paperclip's loopback bind.
CHANGED="$(python3 - "$CONFIG" "$DNS" <<'PY'
import json,os,pathlib,sys,tempfile
p=pathlib.Path(sys.argv[1]); hostname=sys.argv[2]
cfg=json.loads(p.read_text())
old=json.dumps(cfg,sort_keys=True)
s=cfg["server"]; a=cfg["auth"]
if s["deploymentMode"]!="authenticated" or s["exposure"]!="private" or s["bind"]!="loopback":
    raise SystemExit("Safety stop: Paperclip exposure/bind changed")
s["host"]="127.0.0.1"
names=s.get("allowedHostnames",[])
if not isinstance(names,list): raise SystemExit("Invalid Paperclip allowedHostnames")
s["allowedHostnames"]=sorted(set(names+[hostname]))
a["baseUrlMode"]="explicit"
a["publicBaseUrl"]="https://"+hostname
if json.dumps(cfg,sort_keys=True)==old:
    print("NO")
else:
    fd, tmp=tempfile.mkstemp(dir=p.parent,prefix=".config-tailnet-",text=True)
    try:
        with os.fdopen(fd,"w") as out:
            json.dump(cfg,out,indent=2)
            out.write("\n")
        os.chmod(tmp,0o600)
        owner=p.stat()
        os.chown(tmp,owner.st_uid,owner.st_gid)
        os.replace(tmp,p)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print("YES")
PY
)"
if [ "$CHANGED" = YES ]; then
  systemctl restart te-paperclip-cos.service
  sleep 3
fi
if ! curl -fsS --max-time 8 http://127.0.0.1:3100/api/health >/dev/null; then
  printf 'STATE=PAPERCLIP_HEALTH_FAILED\n' >"$STATUS"
  chmod 0600 "$STATUS"
  exit 1
fi
# Reuse existing Serve if already bound, otherwise configure private HTTPS.
if ! /usr/bin/tailscale serve status --json 2>/dev/null | grep -Fq '127.0.0.1:3100'; then
  set +e
  timeout 20 /usr/bin/tailscale serve --yes --bg --https=443 http://127.0.0.1:3100 >"$DIR/serve-attempt.log" 2>&1
  RC=$?
  set -e
  if [ "$RC" -ne 0 ]; then
    printf 'STATE=AWAITING_TAILSCALE_HTTPS_OR_SERVE_APPROVAL\nDASHBOARD=%s\n' "$URL" >"$STATUS"
    chmod 0600 "$STATUS"
    exit 0
  fi
fi
printf 'STATE=READY\nDASHBOARD=%s\nPAPERCLIP=AUTHENTICATED_PRIVATE\nSERVE=TAILNET_ONLY\n' "$URL" >"$STATUS"
chmod 0600 "$STATUS"
FINISH
chmod 0700 /usr/local/sbin/te-cos-tailnet-finalize.sh

cat >/etc/systemd/system/te-cos-tailnet-finalize.service <<'UNIT'
[Unit]
Description=Finish private HTTPS access to Paperclip when Tailscale connects
After=network-online.target tailscaled.service te-paperclip-cos.service
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/te-cos-tailnet-finalize.sh
TimeoutStartSec=75
UNIT
cat >/etc/systemd/system/te-cos-tailnet-finalize.timer <<'UNIT'
[Unit]
Description=Retry private Paperclip HTTPS setup after tailnet authorisation
[Timer]
OnBootSec=20s
OnUnitInactiveSec=45s
Unit=te-cos-tailnet-finalize.service
[Install]
WantedBy=timers.target
UNIT
cat >/etc/systemd/system/te-cos-tailnet-login.service <<'UNIT'
[Unit]
Description=Join Paperclip VM to an explicitly authorised Tailscale tailnet
After=network-online.target tailscaled.service
Wants=network-online.target
[Service]
Type=simple
ExecStart=/usr/bin/tailscale up --hostname=te-chief-of-staff --accept-dns=false --accept-routes=false --ssh=false
StandardOutput=append:/var/lib/te-cos-tailnet/login.log
StandardError=append:/var/lib/te-cos-tailnet/login.log
TimeoutStartSec=infinity
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now te-cos-tailnet-finalize.timer
echo "AUTOMATIC_TAILSCALE_HTTPS_FINALIZER=INSTALLED"

RUNNING=NO
if /usr/bin/tailscale status --json 2>/dev/null | python3 -c 'import json,sys;sys.exit(0 if json.load(sys.stdin).get("BackendState")=="Running" else 1)'; then RUNNING=YES; fi
if [ "$RUNNING" = YES ]; then
  systemctl start --no-block te-cos-tailnet-finalize.service
  echo "TAILSCALE_ALREADY_AUTHENTICATED=YES"
else
  echo "=== REQUEST PHONE SIGN-IN LINK ==="
  systemctl start --no-block te-cos-tailnet-login.service
  # The login process remains active in its own systemd unit, independent of
  # the short-lived Azure VM RunCommand session.
  for i in $(seq 1 30); do
    if grep -Eo 'https://login\.tailscale\.com/a/[[:alnum:]-]+' /var/lib/te-cos-tailnet/login.log | head -n 1 >/dev/null 2>&1 && [ -s /var/lib/te-cos-tailnet/login.log ]; then
      LOGIN_LINK="$(grep -Eo 'https://login\.tailscale\.com/a/[[:alnum:]-]+' /var/lib/te-cos-tailnet/login.log | head -n 1 || true)"
      if [ -n "$LOGIN_LINK" ]; then
        echo "TAILSCALE_PHONE_AUTHORISATION_URL=$LOGIN_LINK"
        break
      fi
    fi
    sleep 1
  done
  if [ -z "$(grep -Eo 'https://login\.tailscale\.com/a/[[:alnum:]-]+' /var/lib/te-cos-tailnet/login.log | head -n 1 || true)" ]; then
    echo "PHONE_AUTH_LINK_NOT_YET_PRINTED=Check Tailscale login unit status. Login is running independently."
  fi
fi
echo "=== CURRENT ACCESS STATE ==="
/usr/local/sbin/te-cos-tailnet-finalize.sh || true
cat /var/lib/te-cos-tailnet/status.txt 2>/dev/null || true
echo "=== PAPERCLIP ADMIN INVITATION (SENSITIVE — KEEP PRIVATE) ==="
# Store nothing in a repository. The one-time invite is output only to this
# authenticated Azure Cloud Shell session. Replace localhost with the final
# Tailscale HTTPS hostname, retaining the /invite/ path and token.
(
  cd /home/tepilot
  runuser -u tepilot -- env \
    -u OPENAI_API_KEY -u CODEX_API_KEY \
    HOME=/home/tepilot \
    PAPERCLIP_HOME=/home/tepilot/paperclip-cos \
    PATH=/opt/te-paperclip/node/bin:/home/tepilot/.local/bin:/usr/local/bin:/usr/bin:/bin \
    /home/tepilot/.local/bin/paperclipai auth bootstrap-ceo \
      --data-dir /home/tepilot/paperclip-cos \
      --base-url http://127.0.0.1:3100 \
      --expires-hours 72
) || echo "ADMIN_INVITE=Could not create; check authenticated Paperclip signup later"
echo "ADMIN_INVITE_INSTRUCTION=Use the invite link above but replace http://127.0.0.1:3100 with your Tailscale HTTPS URL after joining."
echo "IMPORTANT=Do not paste Tailscale authorisation URLs or Paperclip admin invite tokens into chat or GitHub."
echo "NEXT_PHONE_STEPS=Open the Tailscale authorisation link above; enable MagicDNS and HTTPS certificates in the Tailscale admin DNS settings; connect Android Tailscale to the same tailnet."
echo "FIND_ADDRESS=Open the Tailscale Machines page and select te-chief-of-staff; the browser URL is https://<machine>.<tailnet>.ts.net"
echo "CLOUDFLARE=UNMODIFIED"
echo "PUBLIC_INGRESS=NONE"
echo "TAILSCALE_FUNNEL=NOT_ENABLED"
echo "PAPERCLIP_TAILNET_BOOTSTRAP=READY_FOR_PHONE_SIGN_IN"
