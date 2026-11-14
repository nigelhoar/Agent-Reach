#!/usr/bin/env bash
# Run interactively in Azure Cloud Shell once a restricted OpenAI tunnel runtime key exists.
# The key is read silently and stored in a dedicated Azure Key Vault, never printed.
set -euo pipefail
SUB=376a6b21-3fa4-493d-91ac-ba160a0324cd
RG=rg-te-agent-reach-dev
VM=vm-te-agent-reach-dev
VAULT=kv-te-agreach-376a6b
az account set --subscription "$SUB"
az group show --name "$RG" --query name -o tsv
if ! az keyvault show -n "$VAULT" -g "$RG" >/dev/null 2>&1; then
  az keyvault create --subscription "$SUB" -g "$RG" -n "$VAULT" \
    -l uksouth --enable-rbac-authorization true --public-network-access Enabled \
    --only-show-errors -o none
fi
KV_ID="$(az keyvault show -n "$VAULT" -g "$RG" --query id -o tsv)"
USER_ID="$(az ad signed-in-user show --query id -o tsv)"
VM_ID="$(az vm show --subscription "$SUB" -g "$RG" -n "$VM" --query identity.principalId -o tsv)"
test -n "$USER_ID" && test -n "$VM_ID"
if ! az role assignment list --scope "$KV_ID" --assignee "$USER_ID" \
     --query "[?roleDefinitionName=='Key Vault Secrets Officer'].id" -o tsv | grep -q .; then
  az role assignment create --assignee-object-id "$USER_ID" \
    --assignee-principal-type User --role "Key Vault Secrets Officer" \
    --scope "$KV_ID" --only-show-errors -o none
fi
if ! az role assignment list --scope "$KV_ID" --assignee "$VM_ID" \
     --query "[?roleDefinitionName=='Key Vault Secrets User'].id" -o tsv | grep -q .; then
  az role assignment create --assignee-object-id "$VM_ID" \
    --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" \
    --scope "$KV_ID" --only-show-errors -o none
fi

umask 077
KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT
echo "Paste the restricted OpenAI tunnel runtime API key below (input is hidden)."
IFS= read -r -s -p "Runtime API key: " RUNTIME_KEY
echo
test -n "$RUNTIME_KEY" || { echo "Empty key, aborting"; exit 1; }
printf '%s' "$RUNTIME_KEY" > "$KEY_FILE"
unset RUNTIME_KEY
az keyvault secret set --vault-name "$VAULT" --name openai-tunnel-runtime-key \
  --file "$KEY_FILE" --encoding utf-8 --only-show-errors -o none
rm -f "$KEY_FILE"
trap - EXIT

echo "Key securely stored; activating tunnel service with VM managed identity..."
az vm run-command invoke --subscription "$SUB" -g "$RG" -n "$VM" \
  --command-id RunShellScript \
  --scripts "set -eu; cd /opt/agent-reach/source; git fetch origin feature/read-only-chatgpt-mcp; git checkout -B feature/read-only-chatgpt-mcp origin/feature/read-only-chatgpt-mcp; bash deploy/te-readonly-mcp/activate-tunnel.sh $VAULT" \
  --query 'value[].message' -o tsv
