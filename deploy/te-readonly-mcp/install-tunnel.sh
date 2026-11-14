#!/usr/bin/env bash
# Install an official, checksum-verified OpenAI tunnel-client release for Agent Reach.
# No API key is used or recorded here. Run as root via Azure VM Run Command.
set -euo pipefail
TUNNEL_ID="${1:?Usage: install-tunnel.sh tunnel_...}"
case "$TUNNEL_ID" in tunnel_*) ;; *) echo "Invalid tunnel ID" >&2; exit 2;; esac
ROOT=/opt/agent-reach
SOURCE="$ROOT/source/deploy/te-readonly-mcp/server.py"
test -f "$SOURCE" || { echo "Missing MCP source: $SOURCE" >&2; exit 1; }
test -x "$ROOT/mcp-venv/bin/python" || { echo "Run install.sh for MCP first" >&2; exit 1; }
test -x "$ROOT/venv/bin/agent-reach" || { echo "Agent Reach CLI missing" >&2; exit 1; }

TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
RELEASE_JSON="$TEMP/release.json"
curl --fail --silent --show-error --location --retry 3 \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/openai/tunnel-client/releases/latest > "$RELEASE_JSON"
TAG="$(jq -r '.tag_name // empty' "$RELEASE_JSON")"
test -n "$TAG" || { echo "No release tag returned" >&2; exit 1; }
ARCHIVE="tunnel-client-${TAG}-linux-amd64.zip"
ASSET_URL="$(jq -r --arg name "$ARCHIVE" '.assets[] | select(.name==$name) | .browser_download_url' "$RELEASE_JSON" | head -n 1)"
SUM_URL="$(jq -r '.assets[] | select(.name=="SHA256SUMS.txt") | .browser_download_url' "$RELEASE_JSON" | head -n 1)"
test -n "$ASSET_URL" && test -n "$SUM_URL" || { echo "Release lacks expected Linux amd64 asset or checksums: $TAG" >&2; exit 1; }
cd "$TEMP"
curl --fail --silent --show-error --location --retry 3 "$ASSET_URL" -o "$ARCHIVE"
curl --fail --silent --show-error --location --retry 3 "$SUM_URL" -o SHA256SUMS.txt
grep -F "  $ARCHIVE" SHA256SUMS.txt | sha256sum --check -
mkdir extracted
python3 -m zipfile -e "$ARCHIVE" extracted
BIN="$(find "$TEMP/extracted" -type f -name tunnel-client -print -quit)"
test -n "$BIN" || { echo "No tunnel-client executable in official archive" >&2; exit 1; }
install -o root -g root -m 0755 "$BIN" /usr/local/bin/tunnel-client
/usr/local/bin/tunnel-client --version

if ! id agentreach >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/agent-reach-mcp --shell /usr/sbin/nologin agentreach
fi
install -d -o agentreach -g agentreach -m 0700 /var/lib/agent-reach-mcp
install -d -o root -g root -m 0700 /etc/agent-reach
cat >/etc/systemd/system/te-agent-reach-tunnel.service <<EOF
[Unit]
Description=Private OpenAI Secure MCP Tunnel - Agent Reach
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=agentreach
Group=agentreach
WorkingDirectory=/var/lib/agent-reach-mcp
Environment=HOME=/var/lib/agent-reach-mcp
LoadCredential=control-plane-key:/etc/agent-reach/control-plane-api-key
ExecStart=/usr/local/bin/tunnel-client run --control-plane.tunnel-id=$TUNNEL_ID --control-plane.api-key=file:/run/credentials/te-agent-reach-tunnel.service/control-plane-key --mcp.command="/opt/agent-reach/mcp-venv/bin/python /opt/agent-reach/source/deploy/te-readonly-mcp/server.py" --health.listen-addr=127.0.0.1:8082
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/agent-reach-mcp

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
echo "Installed tunnel-client $TAG and prepared te-agent-reach-tunnel.service"
if [ -s /etc/agent-reach/control-plane-api-key ]; then
  systemctl enable --now te-agent-reach-tunnel.service
  systemctl is-active te-agent-reach-tunnel.service
else
  echo "Service deliberately NOT started: runtime key is not yet provisioned."
  echo "Provision /etc/agent-reach/control-plane-api-key securely (root:root 0600), then:"
  echo "  systemctl enable --now te-agent-reach-tunnel.service"
fi
