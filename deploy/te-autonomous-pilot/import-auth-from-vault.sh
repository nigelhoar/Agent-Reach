#!/usr/bin/env bash
# Import a one-time Codex ChatGPT subscription credential from Azure Key Vault.
# Never print, log, or expose the token. Used only on the existing TE-IT-Dev VM.
set -euo pipefail
VAULT="${1:?Vault required}"
SECRET="${2:?Secret name required}"
HOME_DIR=/home/tepilot
AUTH_DIR="$HOME_DIR/.codex"
AUTH_FILE="$AUTH_DIR/auth.json"
CODEX="$HOME_DIR/.local/node_modules/.bin/codex"
NODE=/opt/te-ai-pilot/node/bin

id tepilot >/dev/null
test -x "$CODEX"
# Ensure the pilot user cannot access the VM's managed identity credentials.
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT

install -d -m 0700 -o tepilot -g tepilot "$AUTH_DIR"
umask 077
TMP="$(mktemp "$AUTH_DIR/.auth-import.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
META="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net"
# Root-only action: retrieve short-lived Azure IMDS access token for Key Vault.
AZ_TOKEN="$(curl -fsS --max-time 15 --noproxy '*' -H 'Metadata: true' "$META" | jq -er .access_token)"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$TMP" "$RESPONSE_FILE"' EXIT
HTTP_STATUS="$(curl -sS --max-time 30 --output "$RESPONSE_FILE" --write-out '%{http_code}' \
  -H "Authorization: Bearer $AZ_TOKEN" \
  "https://${VAULT}.vault.azure.net/secrets/${SECRET}?api-version=7.4")"
unset AZ_TOKEN
if [ "$HTTP_STATUS" != "200" ]; then
  echo "Vault secret retrieval failed: HTTP $HTTP_STATUS" >&2
  exit 1
fi

jq -er '.value' "$RESPONSE_FILE" > "$TMP"
rm -f "$RESPONSE_FILE"
python3 - "$TMP" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
if data.get('auth_mode') != 'chatgpt':
    raise SystemExit('STOP: imported credentials are not ChatGPT subscription authentication')
if not isinstance(data.get('tokens'), dict):
    raise SystemExit('STOP: ChatGPT session token structure absent')
print('Authenticated mode: ChatGPT subscription (structure verified; tokens withheld)')
PY
chown tepilot:tepilot "$TMP"
chmod 0600 "$TMP"
mv -f "$TMP" "$AUTH_FILE"
trap - EXIT

# Check official Codex CLI sign-in method, not an API-key path.
STATUS="$(runuser -u tepilot -- env -u OPENAI_API_KEY -u CODEX_API_KEY \
  HOME="$HOME_DIR" CODEX_HOME="$AUTH_DIR" \
  PATH="$NODE:$HOME_DIR/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
  "$CODEX" login status 2>&1)" || { echo "Official Codex login status failed"; exit 1; }
case "$STATUS" in
  *"Logged in using ChatGPT"*) ;;
  *) echo "STOP: Codex did not confirm ChatGPT login"; exit 1 ;;
esac
test "$(stat -c %a "$AUTH_FILE")" = "600"
echo "SUBSCRIPTION_LOGIN_OK: Codex runs under tepilot using ChatGPT; authentication file is mode 0600."
