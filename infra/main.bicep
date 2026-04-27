targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Resource name prefix')
param namePrefix string = 'teamsagent'

@description('App Service plan name for the proxy Web App')
param appServicePlanName string = '${namePrefix}-asp'

@description('Proxy Web App name')
param proxyWebAppName string = '${namePrefix}-proxy-web'

@description('Azure Front Door profile name')
param afdProfileName string = '${namePrefix}-afd'

@description('Azure Front Door endpoint name')
param afdEndpointName string = '${namePrefix}-edge'

@description('Private base URL of the internal Container App, e.g. http://teamsagent-app-westus2.internal.<env>.<region>.azurecontainerapps.io')
param privateContainerAppBaseUrl string = 'http://teamsagent-app-westus2'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${namePrefix}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource proxyWebApp 'Microsoft.Web/sites@2023-12-01' = {
  name: proxyWebAppName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appCommandLine: 'python src/proxy_app.py'
      alwaysOn: true
      appSettings: [
        {
          name: 'PROXY_UPSTREAM_BASE_URL'
          value: privateContainerAppBaseUrl
        }
        {
          name: 'PROXY_TIMEOUT_SECONDS'
          value: '60'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8000'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
    }
    httpsOnly: true
  }
}

resource afdProfile 'Microsoft.Cdn/profiles@2024-05-01-preview' = {
  name: afdProfileName
  location: 'global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
}

resource afdEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-05-01-preview' = {
  parent: afdProfile
  name: afdEndpointName
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource afdOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-05-01-preview' = {
  parent: afdProfile
  name: '${namePrefix}-proxy-og'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/healthz'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 120
    }
    sessionAffinityState: 'Disabled'
  }
}

resource afdOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-05-01-preview' = {
  parent: afdOriginGroup
  name: '${namePrefix}-proxy-origin'
  properties: {
    hostName: proxyWebApp.properties.defaultHostName
    originHostHeader: proxyWebApp.properties.defaultHostName
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

resource afdRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-05-01-preview' = {
  parent: afdEndpoint
  name: '${namePrefix}-bot-route'
  dependsOn: [
    afdOrigin
  ]
  properties: {
    originGroup: {
      id: afdOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/api/messages'
      '/api/messages/*'
      '/healthz'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
}

output proxyWebAppHostname string = proxyWebApp.properties.defaultHostName
output afdHostname string = afdEndpoint.properties.hostName
output botEndpoint string = 'https://${afdEndpoint.properties.hostName}/api/messages'
output privateUpstreamConfigured string = privateContainerAppBaseUrl
