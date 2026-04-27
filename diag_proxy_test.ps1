$ErrorActionPreference="Continue"
function Invoke-DiagPost { param([string]$Name,[string]$Url)
  $status="ERR"; $body=""
  $jsonBody='{"type":"message","id":"diag-'+[guid]::NewGuid().ToString()+'","timestamp":"2026-04-22T00:00:00Z","serviceUrl":"https://smba.trafficmanager.net/amer/","channelId":"msteams","from":{"id":"u1"},"conversation":{"id":"c1"},"recipient":{"id":"b1"},"text":"ping"}'
  try { $resp=Invoke-WebRequest -Method Post -Uri $Url -ContentType "application/json" -Body $jsonBody -TimeoutSec 30 -SkipHttpErrorCheck; if($resp.StatusCode){$status=[int]$resp.StatusCode}; if($resp.Content){$body=$resp.Content} }
  catch { if($_.Exception.Response -and $_.Exception.Response.StatusCode){$status=[int]$_.Exception.Response.StatusCode}; if($_.Exception.Message){$body=$_.Exception.Message} }
  if($null -eq $body){$body=""}; $body=$body.ToString(); if($body.Length -gt 200){$body=$body.Substring(0,200)}
  [pscustomobject]@{target=$Name;url=$Url;status=$status;body200=$body}
}

$rgProxy="rg-teams-agent-proxy-westus2"; $webapp="teamsagent-proxy-web"
$rgCa="rg-teams-agent"; $ca="teamsagent-app-westus2"
$webappHost="teamsagent-proxy-web.azurewebsites.net"
$afdUrl="https://teamsagent-edge-clean-gshjcqfdgsf9b2g7.b01.azurefd.net/api/messages"

Write-Host "STEP1_READ_CURRENT_SETTINGS_START"
$settingsJson = az webapp config appsettings list -g $rgProxy -n $webapp --query "[?name=='PROXY_UPSTREAM_BASE_URL'||name=='PROXY_UPSTREAM_HOST_HEADER'||name=='PROXY_TIMEOUT_SECONDS'].{name:name,value:value}" -o json
$settings = $settingsJson | ConvertFrom-Json
$oldBase = ($settings | Where-Object name -eq "PROXY_UPSTREAM_BASE_URL" | Select-Object -First 1).value
$oldHost = ($settings | Where-Object name -eq "PROXY_UPSTREAM_HOST_HEADER" | Select-Object -First 1).value
$oldTimeout = ($settings | Where-Object name -eq "PROXY_TIMEOUT_SECONDS" | Select-Object -First 1).value
[pscustomobject]@{oldBase=$oldBase;oldHost=$oldHost;oldTimeout=$oldTimeout} | ConvertTo-Json -Compress | Write-Host
Write-Host "STEP1_READ_CURRENT_SETTINGS_END"

Write-Host "STEP2_CONTAINERAPP_INGRESS_START"
$caJson = az containerapp show -g $rgCa -n $ca --query "{fqdn:properties.configuration.ingress.fqdn,external:properties.configuration.ingress.external,targetPort:properties.configuration.ingress.targetPort}" -o json
$caObj = $caJson | ConvertFrom-Json
$newBase = "http://$($caObj.fqdn)"
$newHostHeader = "$($caObj.fqdn)"
[pscustomobject]@{fqdn=$caObj.fqdn;external=$caObj.external;targetPort=$caObj.targetPort;newBase=$newBase;newHostHeader=$newHostHeader} | ConvertTo-Json -Compress | Write-Host
Write-Host "STEP2_CONTAINERAPP_INGRESS_END"

Write-Host "STEP3_SWITCH_TO_PRIVATE_UPSTREAM_START"
az webapp config appsettings set -g $rgProxy -n $webapp --settings PROXY_UPSTREAM_BASE_URL=$newBase PROXY_UPSTREAM_HOST_HEADER=$newHostHeader PROXY_TIMEOUT_SECONDS=120 --output none
$healthResults=@()
for($i=1;$i -le 10;$i++){
  $code="ERR"
  try { $r=Invoke-WebRequest -Uri ("https://$webappHost/healthz") -Method Get -TimeoutSec 20 -SkipHttpErrorCheck; if($r.StatusCode){$code=[int]$r.StatusCode} }
  catch { if($_.Exception.Response -and $_.Exception.Response.StatusCode){$code=[int]$_.Exception.Response.StatusCode} }
  $healthResults += [pscustomobject]@{try=$i;status=$code}
}
$healthResults | ConvertTo-Json -Compress | Write-Host
Write-Host "STEP3_SWITCH_TO_PRIVATE_UPSTREAM_END"

Write-Host "STEP4_CONNECTIVITY_PROBES_START"
$pWeb = Invoke-DiagPost -Name "WEBAPP_PROXY" -Url ("https://$webappHost/api/messages")
$pAfd = Invoke-DiagPost -Name "AFD_CLEAN" -Url $afdUrl
@($pWeb,$pAfd) | ConvertTo-Json -Compress | Write-Host
Write-Host "STEP4_CONNECTIVITY_PROBES_END"

Write-Host "STEP4_LOG_DOWNLOAD_AND_FILTER_START"
$zipPath = Join-Path (Get-Location) "diag_webapp_logs.zip"
$extractPath = Join-Path (Get-Location) "diag_webapp_logs"
if(Test-Path $zipPath){Remove-Item $zipPath -Force -ErrorAction SilentlyContinue}
if(Test-Path $extractPath){Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue}
$dl = az webapp log download -g $rgProxy -n $webapp --log-file $zipPath 2>&1
if(Test-Path $zipPath){
  Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
  $patterns = "Proxy forwarding request|Proxy upstream response|Upstream call failed"
  $matches = Get-ChildItem -Path $extractPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Select-String -Path $_.FullName -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue } catch {}
  }
  if($matches){
    $last20 = $matches | Select-Object -Last 20
    Write-Host "LOG_MATCHES_START"
    foreach($m in $last20){ $line=$m.Line; if($line.Length -gt 400){$line=$line.Substring(0,400)}; Write-Host $line }
    Write-Host "LOG_MATCHES_END"
  } else {
    Write-Host "LOG_MATCHES_NONE"
  }
} else {
  Write-Host "LOG_DOWNLOAD_FAILED"
  $dl | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
}
Write-Host "STEP4_LOG_DOWNLOAD_AND_FILTER_END"

Write-Host "STEP5_ROLLBACK_START"
$restoreSettings = @()
if($null -ne $oldBase -and $oldBase -ne ""){$restoreSettings += "PROXY_UPSTREAM_BASE_URL=$oldBase"}
if($null -ne $oldHost -and $oldHost -ne ""){$restoreSettings += "PROXY_UPSTREAM_HOST_HEADER=$oldHost"}
if($null -ne $oldTimeout -and $oldTimeout -ne ""){$restoreSettings += "PROXY_TIMEOUT_SECONDS=$oldTimeout"}
if($restoreSettings.Count -gt 0){ az webapp config appsettings set -g $rgProxy -n $webapp --settings $restoreSettings --output none } else { Write-Host "ROLLBACK_WARNING_NO_OLD_SETTINGS_FOUND" }
$healthBack=@()
for($i=1;$i -le 10;$i++){
  $code="ERR"
  try { $r=Invoke-WebRequest -Uri ("https://$webappHost/healthz") -Method Get -TimeoutSec 20 -SkipHttpErrorCheck; if($r.StatusCode){$code=[int]$r.StatusCode} }
  catch { if($_.Exception.Response -and $_.Exception.Response.StatusCode){$code=[int]$_.Exception.Response.StatusCode} }
  $healthBack += [pscustomobject]@{try=$i;status=$code}
}
$healthBack | ConvertTo-Json -Compress | Write-Host
$pRollback = Invoke-DiagPost -Name "WEBAPP_AFTER_ROLLBACK" -Url ("https://$webappHost/api/messages")
$pRollback | ConvertTo-Json -Compress | Write-Host
$finalSettings = az webapp config appsettings list -g $rgProxy -n $webapp --query "[?name=='PROXY_UPSTREAM_BASE_URL'||name=='PROXY_UPSTREAM_HOST_HEADER'||name=='PROXY_TIMEOUT_SECONDS'].{name:name,value:value}" -o json
Write-Host "FINAL_SETTINGS_START"; Write-Host $finalSettings; Write-Host "FINAL_SETTINGS_END"
Write-Host "STEP5_ROLLBACK_END"
