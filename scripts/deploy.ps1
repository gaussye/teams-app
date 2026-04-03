param(
    [Parameter(Mandatory = $true)] [string]$SubscriptionId,
    [Parameter(Mandatory = $true)] [string]$ResourceGroup,
    [Parameter(Mandatory = $true)] [string]$Location,
    [Parameter(Mandatory = $true)] [string]$NamePrefix,
    [Parameter(Mandatory = $true)] [string]$BotAppId,
  [Parameter(Mandatory = $true)] [string]$BotTenantId,
    [Parameter(Mandatory = $true)] [string]$BotAppPassword,
    [Parameter(Mandatory = $true)] [string]$FoundryEndpoint,
    [Parameter(Mandatory = $true)] [string]$FoundryModelId,
    [Parameter(Mandatory = $true)] [string]$FoundryApiKey
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $true
}

Write-Host "[1/9] Set subscription"
az account set --subscription $SubscriptionId

Write-Host "[2/9] Create resource group"
az group create --name $ResourceGroup --location $Location | Out-Null

$acrName = ($NamePrefix + "acr").ToLower()
$caeName = "$NamePrefix-cae"
$appName = "$NamePrefix-app"
$lawName = "$NamePrefix-law"
$botName = "$NamePrefix-bot-$((Get-Random -Minimum 10000 -Maximum 99999))"
$image = "$acrName.azurecr.io/teams-agent:latest"

Write-Host "[3/9] Create ACR"
az acr create --resource-group $ResourceGroup --name $acrName --sku Basic --admin-enabled true | Out-Null

Write-Host "[4/9] Build and push container image"
az acr build --registry $acrName --image teams-agent:latest --no-logs . | Out-Null

$acrUser = az acr credential show --name $acrName --resource-group $ResourceGroup --query username -o tsv
$acrPass = az acr credential show --name $acrName --resource-group $ResourceGroup --query passwords[0].value -o tsv

Write-Host "[5/9] Create Log Analytics"
az monitor log-analytics workspace create --resource-group $ResourceGroup --workspace-name $lawName --location $Location | Out-Null

$customerId = az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $lawName --query customerId -o tsv
$sharedKey = az monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $lawName --query primarySharedKey -o tsv

Write-Host "[6/9] Create Container Apps environment"
az containerapp env create --name $caeName --resource-group $ResourceGroup --location $Location --logs-workspace-id $customerId --logs-workspace-key $sharedKey | Out-Null

Write-Host "[7/9] Create Container App"
az containerapp create `
  --name $appName `
  --resource-group $ResourceGroup `
  --environment $caeName `
  --image $image `
  --registry-server "$acrName.azurecr.io" `
  --registry-username $acrUser `
  --registry-password $acrPass `
  --target-port 3978 `
  --ingress external `
  --cpu 0.5 `
  --memory 1.0Gi `
  --min-replicas 1 `
  --max-replicas 3 `
  --secrets bot-app-password=$BotAppPassword foundry-api-key=$FoundryApiKey `
  --env-vars BOT_APP_ID=$BotAppId BOT_APP_PASSWORD=secretref:bot-app-password BOT_APP_TENANT_ID=$BotTenantId FOUNDRY_ENDPOINT=$FoundryEndpoint FOUNDRY_MODEL_ID=$FoundryModelId FOUNDRY_API_KEY=secretref:foundry-api-key SYSTEM_PROMPT="You are a helpful assistant in Microsoft Teams." | Out-Null

$fqdn = az containerapp show --name $appName --resource-group $ResourceGroup --query properties.configuration.ingress.fqdn -o tsv
$endpoint = "https://$fqdn/api/messages"

Write-Host "[8/9] Create Azure Bot Service"
az bot create --resource-group $ResourceGroup --name $botName --endpoint $endpoint --appid $BotAppId --app-type SingleTenant --tenant-id $BotTenantId | Out-Null

Write-Host "[9/9] Enable Teams channel"
az bot msteams create --resource-group $ResourceGroup --name $botName | Out-Null

Write-Host "Deployment completed."
Write-Host "Container App endpoint: $endpoint"
Write-Host "Bot name: $botName"
Write-Host "Next: replace botId in teams/manifest.json and upload package to Teams."
