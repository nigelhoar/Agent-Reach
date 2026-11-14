#!/usr/bin/env bash
# Taylor Emmet Chief of Staff: isolated, authenticated Paperclip on existing VM.
# Run as root through Azure VM RunCommand. Does NOT open firewall ports or
# start autonomous coding jobs. Existing Node22/Codex/AoE remain untouched.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
H=/home/tepilot
ROOT=/opt/te-paperclip
NODE="$ROOT/node/bin"
CLI="$H/.local/bin/paperclipai"
STATE="$H/paperclip-cos"
SERVICE=te-paperclip-cos.service
echo "=== PAPERCLIP PRECHECK ==="
test "$(id -un)" = root
test -d "$H" && id tepilot >/dev/null
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT
if systemctl is-active --quiet "$SERVICE"; then
  echo "Service exists; checking existing instance instead of reinstalling."
  curl -fsS --max-time 15 http://127.0.0.1:3100/api/health | head -c 700
  echo; echo "PAPERCLIP_ALREADY_RUNNING=YES"
  exit 0
fi
apt-get update -qq
apt-get install -y -qq ca-certificates curl jq xz-utils python3 git
install -d -m 0755 "$ROOT"
if [ ! -x "$NODE/node" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL --retry 3 https://nodejs.org/dist/index.json -o "$TMP/index.json"
  VERSION="$(jq -er '[.[] | select(.version | startswith("v24."))][0].version' "$TMP/index.json")"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) ARCH=x64;;
    aarch64) ARCH=arm64;;
    *) echo "Unsupported processor architecture: $ARCH"; exit 1;;
  esac
  FILE="node-$VERSION-linux-$ARCH.tar.xz"
  URL="https://nodejs.org/dist/$VERSION"
  curl -fsSL --retry 3 "$URL/$FILE" -o "$TMP/$FILE"
  curl -fsSL --retry 3 "$URL/SHASUMS256.txt" -o "$TMP/SHASUMS256.txt"
  (cd "$TMP"; grep -F "  $FILE" SHASUMS256.txt | sha256sum -c -)
  install -d -m 0755 "$ROOT/node"
  tar -xJf "$TMP/$FILE" -C "$ROOT/node" --strip-components=1
fi
"$NODE/node" --version
run_pilot() {
  # Azure RunCommand invokes commands from an inaccessible /var/lib/waagent
  # working directory. npm/npx child processes fail with spawn sh EACCES
  # unless root changes to a directory visible to tepilot BEFORE runuser.
  (
    cd "$H"
    runuser -u tepilot -- env \
      -u OPENAI_API_KEY -u CODEX_API_KEY \
      HOME="$H" CODEX_HOME="$H/.codex" \
      PATH="$NODE:$H/.local/bin:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
      PAPERCLIP_NO_BROWSER=1 \
      PAPERCLIP_DEPLOYMENT_MODE=authenticated \
      PAPERCLIP_DEPLOYMENT_EXPOSURE=private \
      PAPERCLIP_BIND=loopback \
      "$@"
  )
}
test "$("$NODE/node" -p 'Number(process.versions.node.split(".")[0])')" -eq 24
echo "=== INSTALL MANAGED PAPERCLIP CLI ==="
if [ ! -x "$CLI" ]; then
  run_pilot "$NODE/npx" --yes paperclipai@latest install --yes
fi
run_pilot "$CLI" --version
install -d -m 0700 -o tepilot -g tepilot "$STATE"
# The standard CLI --yes quickstart starts the server. Bound that one-time
# setup with timeout, then enforce authenticated+loopback in config and run
# under a controlled system unit. Even temporary onboarding stays loopback-only.
if ! find "$STATE" -type f -name config.json -print -quit | grep -q .; then
  echo "=== INITIAL CONFIGURATION ==="
  install -m 0600 -o tepilot -g tepilot /dev/null "$STATE/initial-onboard.log"
  set +e
  run_pilot timeout --signal=TERM --kill-after=5s 80s \
    "$CLI" onboard --yes --bind loopback --no-install-service \
    --data-dir "$STATE" >"$STATE/initial-onboard.log" 2>&1
  SETUP_RC=$?
  set -e
  echo "ONBOARD_EXIT=$SETUP_RC"
  if ! find "$STATE" -type f -name config.json -print -quit | grep -q .; then
    echo "Onboarding did not create configuration; inspect $STATE/initial-onboard.log locally without exposing bootstrap tokens."
    exit 1
  fi
fi
echo "=== ENFORCE PRIVATE AUTHENTICATED MODE ==="
python3 - "$STATE" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
matches=list(root.rglob("config.json"))
if len(matches)!=1:
    raise SystemExit("Expected one isolated instance config, found "+str(len(matches))+"; not guessing")
path=matches[0]
cfg=json.loads(path.read_text())
s=cfg.setdefault("server",{})
s["deploymentMode"]="authenticated"
s["exposure"]="private"
s["bind"]="loopback"
s["host"]="127.0.0.1"
s.pop("customBindHost",None)
a=cfg.setdefault("auth",{})
a["baseUrlMode"]="auto"
a["disableSignUp"]=False
tmp=path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(cfg,indent=2)+"\n")
tmp.chmod(0o600)
tmp.replace(path)
path.chmod(0o600)
print("AUTH_MODE=authenticated/private")
print("SERVER_BIND=127.0.0.1")
print("INSTANCE_CONFIG="+str(path))
PY
chown -R tepilot:tepilot "$STATE"
chmod 0700 "$STATE"
echo "=== INSTALL SUPERVISED SERVICE ==="
cat >/etc/systemd/system/$SERVICE <<UNIT
[Unit]
Description=Taylor Emmet Development Chief of Staff (Paperclip)
After=network-online.target te-ai-pilot-block-imds.service
Wants=network-online.target
Requires=te-ai-pilot-block-imds.service

[Service]
Type=simple
User=tepilot
Group=tepilot
WorkingDirectory=$H
Environment=HOME=$H
Environment=CODEX_HOME=$H/.codex
Environment=PATH=$NODE:$H/.local/bin:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin
Environment=PAPERCLIP_NO_BROWSER=1
Environment=PAPERCLIP_AUTH_RATE_LIMIT_ENABLED=true
Environment=PAPERCLIP_DEPLOYMENT_MODE=authenticated
Environment=PAPERCLIP_DEPLOYMENT_EXPOSURE=private
Environment=PAPERCLIP_BIND=loopback
ExecStart=$CLI run --data-dir $STATE --no-repair
Restart=on-failure
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
UMask=0077
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now "$SERVICE"
echo "=== PROVE HEALTH AND PRIVATE BIND ==="
OK=0
for n in $(seq 1 35); do
  if curl -fsS --max-time 4 http://127.0.0.1:3100/api/health >/dev/null 2>&1; then OK=1; break; fi
  sleep 3
done
if [ "$OK" != 1 ]; then
  echo "Paperclip did not answer healthy; last unit log excerpt:"
  journalctl -u "$SERVICE" -n 30 --no-pager | sed -E 's/pcp_bootstrap_[A-Za-z0-9]+/pcp_bootstrap_[REDACTED]/g; s#(/invite/)[A-Za-z0-9_-]+#\1[REDACTED]#g' | tail -n 30
  exit 1
fi
python3 - <<'PY'
import subprocess
lines=subprocess.check_output(["ss","-ltn"],text=True).splitlines()
ports=[line for line in lines if ":3100 " in line]
if not ports or any("0.0.0.0:3100" in x or "[::]:3100" in x for x in ports):
    raise SystemExit("FAIL: Paperclip socket binding not proven localhost-only")
print("PRIVATE_LISTENER=VERIFIED")
PY
run_pilot "$H/.local/node_modules/.bin/codex" login status
echo "PAPERCLIP_SERVICE=ACTIVE"
echo "PAPERCLIP_HEALTH=OK"
echo "PAPERCLIP_URL_LOCAL_ONLY=http://127.0.0.1:3100"
echo "AGENT_EXECUTION=NOT_ENABLED_BY_BOOTSTRAP"
echo "NEXT=Complete the admin bootstrap through approved private access; portfolio import follows."
