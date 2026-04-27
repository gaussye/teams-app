param(
    [Parameter(Mandatory = $true)] [string]$SubscriptionId,
    [Parameter(Mandatory = $true)] [string]$ResourceGroup,
    [Parameter(Mandatory = $true)] [string]$Location,
    [Parameter(Mandatory = $true)] [string]$NamePrefix,
  [Parameter(Mandatory = $true)] [string]$ExistingBotServiceName,
  [string]$BotResourceGroup = "",
    [Parameter(Mandatory = $true)] [string]$PrivateContainerAppBaseUrl
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $true
}

$proxyWebAppName = "$NamePrefix-proxy-web"
$appServicePlanName = "$NamePrefix-asp"
$afdProfileName = "$NamePrefix-afd"
$afdEndpointName = "$NamePrefix-edge"

if ([string]::IsNullOrWhiteSpace($BotResourceGroup)) {
  $BotResourceGroup = $ResourceGroup
}

Write-Host "[1/8] Set subscription"
az account set --subscription $SubscriptionId

Write-Host "[2/8] Create resource group"
az group create --name $ResourceGroup --location $Location | Out-Null

Write-Host "[3/8] Deploy infrastructure (Web App + AFD)"
$deployment = az deployment group create `
  --resource-group $ResourceGroup `
  --template-file "infra/main.bicep" `
  --parameters `
    location=$Location `
    namePrefix=$NamePrefix `
    appServicePlanName=$appServicePlanName `
    proxyWebAppName=$proxyWebAppName `
    afdProfileName=$afdProfileName `
    afdEndpointName=$afdEndpointName `
    privateContainerAppBaseUrl=$PrivateContainerAppBaseUrl `
  --query properties.outputs -o json | ConvertFrom-Json

Write-Host "[4/8] Package proxy application"
$zipPath = Join-Path $env:TEMP "teams-proxy.zip"
if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}
Compress-Archive -Path "src", "requirements.txt" -DestinationPath $zipPath -Force

Write-Host "[5/8] Deploy proxy code to Web App"
az webapp deploy --resource-group $ResourceGroup --name $proxyWebAppName --src-path $zipPath --type zip | Out-Null

Write-Host "[6/8] Configure startup command and app settings"
az webapp config set --resource-group $ResourceGroup --name $proxyWebAppName --startup-file "python src/proxy_app.py" | Out-Null
az webapp config appsettings set --resource-group $ResourceGroup --name $proxyWebAppName --settings `
  PROXY_UPSTREAM_BASE_URL=$PrivateContainerAppBaseUrl `
  PROXY_TIMEOUT_SECONDS=60 `
  SCM_DO_BUILD_DURING_DEPLOYMENT=true `
  WEBSITES_PORT=8000 | Out-Null

$afdHost = $deployment.afdHostname.value
$botEndpoint = $deployment.botEndpoint.value

Write-Host "[7/8] Update existing Bot endpoint"
az bot update --resource-group $BotResourceGroup --name $ExistingBotServiceName --endpoint $botEndpoint | Out-Null

Write-Host "[8/8] Ensure Teams channel"
try {
  az bot msteams show --resource-group $BotResourceGroup --name $ExistingBotServiceName | Out-Null
}
catch {
  az bot msteams create --resource-group $BotResourceGroup --name $ExistingBotServiceName | Out-Null
}

Write-Host "Deployment completed"
Write-Host "AFD Host: https://$afdHost"
Write-Host "Bot endpoint: $botEndpoint"
Write-Host "Proxy Web App: https://$proxyWebAppName.azurewebsites.net"
Write-Host "Private upstream: $PrivateContainerAppBaseUrl"
Write-Host "Updated existing bot: $ExistingBotServiceName"
