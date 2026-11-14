# Taylor Emmet Codex pilot: one-time secure ChatGPT subscription auth transfer.
# Run in Windows PowerShell only, on the PC where "codex login" succeeded.
$ErrorActionPreference = "Stop"
$Subscription = "376a6b21-3fa4-493d-91ac-ba160a0324cd"
$ResourceGroup = "rg-te-agent-reach-dev"
$Vm = "vm-te-agent-reach-dev"
$Vault = "kv-te-agreach-376a6b"
$AuthFile = Join-Path $env:USERPROFILE ".codex\auth.json"
$SecretName = "codex-pilot-auth-" + (Get-Date -Format "yyyyMMddHHmmss")
$Uploaded = $false
$Success = $false

if (-not (Test-Path -LiteralPath $AuthFile -PathType Leaf)) {
    throw "Codex auth file does not exist. Run codex login on this Windows PC first."
}
$Size = (Get-Item -LiteralPath $AuthFile).Length
if ($Size -gt 22000 -or $Size -lt 100) {
    throw "Unexpected Codex auth file size ($Size bytes); not uploading."
}
$Status = & codex login status 2>&1
if ($LASTEXITCODE -ne 0 -or "$Status" -notmatch "Logged in using ChatGPT") {
    throw "Codex on Windows is not signed into ChatGPT. No transfer attempted."
}
# Check sign-in type only; never print credential JSON.
$AuthMode = (Get-Content -LiteralPath $AuthFile -Raw -Encoding UTF8 | ConvertFrom-Json).auth_mode
if ($AuthMode -ne "chatgpt") {
    throw "Codex auth.json does not specify chatgpt authentication. No transfer attempted."
}
Write-Host "Verified ChatGPT subscription authentication on Windows."

& az account set --subscription $Subscription
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI is not logged into TE-IT-Dev. Run az login, then retry."
}

try {
    Write-Host "Uploading auth securely to an Azure Key Vault one-time secret..."
    & az keyvault secret set --vault-name $Vault --name $SecretName --file $AuthFile --encoding utf-8 --output none
    if ($LASTEXITCODE -ne 0) { throw "Key Vault upload failed." }
    $Uploaded = $true

    # Only a script URI and secret identifier appear in Azure RunCommand,
    # NOT the contents of auth.json.
    $RemoteScript = @"
set -eu
curl --fail --silent --show-error --location --retry 3 -o /tmp/te-codex-import-auth.sh https://raw.githubusercontent.com/nigelhoar/Agent-Reach/80154fd96e346c91fdc861ed69442d6b7a4cde45/deploy/te-autonomous-pilot/import-auth-from-vault.sh
bash /tmp/te-codex-import-auth.sh $Vault $SecretName
"@
    Write-Host "Importing on the isolated VM account..."
    $Raw = & az vm run-command invoke --subscription $Subscription --resource-group $ResourceGroup --name $Vm --command-id RunShellScript --scripts $RemoteScript --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure VM RunCommand failed." }

    $Parsed = ($Raw -join [Environment]::NewLine) | ConvertFrom-Json
    $Messages = @($Parsed.value | ForEach-Object { $_.message }) -join [Environment]::NewLine
    if ($Messages -notmatch "SUBSCRIPTION_LOGIN_OK") {
        Write-Host ("VM diagnostic: " + $Messages.Substring([Math]::Max(0,$Messages.Length-1200)))
        throw "VM did not confirm ChatGPT subscription authentication."
    }
    $Success = $true
    Write-Host "SUCCESS: Codex on the Azure VM is now signed in using the ChatGPT Business subscription."
} finally {
    # Removes one-time secret from normal reads. Key Vault soft-delete retention
    # may apply; the auth file remains locally on the VM for the pilot.
    if ($Uploaded) {
        Write-Host "Deleting the temporary Key Vault secret..."
        & az keyvault secret delete --vault-name $Vault --name $SecretName --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not delete one-time Key Vault secret; inspect Key Vault immediately."
        } else {
            Write-Host "Temporary Key Vault secret deleted from active secrets."
        }
    }
}
if ($Success) {
    Write-Host "NEXT: Verify usage allowances and then run the fixed-time synthetic benchmark."
}
