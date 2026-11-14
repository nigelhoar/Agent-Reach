#!/usr/bin/env bash
# Start official Codex device-code login in a transient, non-root systemd unit.
# No API keys or client secrets are passed to Codex.
set -euo pipefail
U=tepilot
H=/home/tepilot
NODE=/opt/te-ai-pilot/node/bin
CODEX="$H/.local/node_modules/.bin/codex"
test -x "$CODEX" || { echo "Pilot not bootstrapped yet"; exit 1; }
systemctl stop te-codex-device-login.service 2>/dev/null || true
systemctl reset-failed te-codex-device-login.service 2>/dev/null || true
systemd-run \
  --unit=te-codex-device-login \
  --collect \
  --property="User=$U" \
  --property="Group=$U" \
  --property="WorkingDirectory=$H/benchmark" \
  --property="RuntimeMaxSec=600" \
  --property="NoNewPrivileges=yes" \
  --property="ProtectHome=no" \
  --setenv="HOME=$H" \
  --setenv="CODEX_HOME=$H/.codex" \
  --setenv="PATH=$NODE:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
  "$CODEX" login --device-auth
sleep 3
echo "=== DEVICE AUTHORIZATION (visit URL and enter displayed code) ==="
journalctl -u te-codex-device-login.service --no-pager -n 35 -o cat
echo "=== Confirm later ==="
echo "runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY HOME=/home/tepilot PATH=/opt/te-ai-pilot/node/bin:/home/tepilot/.local/node_modules/.bin:/usr/bin:/bin /home/tepilot/.local/node_modules/.bin/codex login status"
