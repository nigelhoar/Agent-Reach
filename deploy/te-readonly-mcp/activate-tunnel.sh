#!/usr/bin/env bash
# On Azure VM: fetch only the Agent Reach tunnel runtime credential via managed identity.
# Requires Key Vault Secrets User for the VM's system-assigned managed identity.
set -euo pipefail
VAULT="${1:?Usage: activate-tunnel.sh key-vault-name}"
SERVICE=te-agent-reach-tunnel.service
install -d -o root -g root -m 0700 /etc/agent-reach
umask 077
FILE="$(mktemp /etc/agent-reach/.runtime-key.XXXXXX)"
trap 'rm -f "$FILE"' EXIT

# IMDS is accessible only from within Azure VM. No Azure CLI or login required.
META='http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net'
TOKEN="$(curl --fail --silent --show-error --noproxy '*' -H Metadata:true "$META" | jq -er .access_token)"
STATUS="$(curl --silent --show-error --output "$FILE.json" --write-out '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  "https://${VAULT}.vault.azure.net/secrets/openai-tunnel-runtime-key?api-version=7.4")"
unset TOKEN
if [ "$STATUS" != 200 ]; then
  echo "Key Vault retrieval failed: HTTP $STATUS" >&2
  rm -f "$FILE.json"
  exit 1
fi
jq -er .value "$FILE.json" > "$FILE"
rm -f "$FILE.json"
test -s "$FILE" || { echo "Empty runtime credential" >&2; exit 1; }
chown root:root "$FILE"
chmod 0600 "$FILE"
mv -f "$FILE" /etc/agent-reach/control-plane-api-key
trap - EXIT
systemctl daemon-reload
systemctl enable --now "$SERVICE"
systemctl is-active "$SERVICE"
echo "Tunnel service started; use systemctl status $SERVICE to inspect status (no secrets shown)."
