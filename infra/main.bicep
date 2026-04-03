targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Resource name prefix')
param namePrefix string = 'teamsagent'

@description('Container image in ACR')
param containerImage string

@description('Bot application ID (Azure AD app id)')
param botAppId string

@secure()
@description('Bot application password/secret')
param botAppPassword string

@description('Foundry endpoint, e.g. https://<endpoint>/openai/v1')
param foundryEndpoint string

@description('Foundry model id/deployment name')
param foundryModelId string

@secure()
@description('Foundry API key')
param foundryApiKey string

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

resource containerEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-cae'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: listKeys(logAnalytics.id, logAnalytics.apiVersion).primarySharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-app'
  location: location
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3978
      }
      secrets: [
        {
          name: 'bot-app-password'
          value: botAppPassword
        }
        {
          name: 'foundry-api-key'
          value: foundryApiKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'teams-agent'
          image: containerImage
          env: [
            {
              name: 'BOT_APP_ID'
              value: botAppId
            }
            {
              name: 'BOT_APP_PASSWORD'
              secretRef: 'bot-app-password'
            }
            {
              name: 'FOUNDRY_ENDPOINT'
              value: foundryEndpoint
            }
            {
              name: 'FOUNDRY_MODEL_ID'
              value: foundryModelId
            }
            {
              name: 'FOUNDRY_API_KEY'
              secretRef: 'foundry-api-key'
            }
            {
              name: 'SYSTEM_PROMPT'
              value: 'You are a helpful assistant in Microsoft Teams.'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: '${namePrefix}-bot'
  location: 'global'
  kind: 'azurebot'
  sku: {
    name: 'F0'
  }
  properties: {
    displayName: '${namePrefix}-bot'
    endpoint: 'https://${containerApp.properties.configuration.ingress.fqdn}/api/messages'
    msaAppType: 'MultiTenant'
    msaAppId: botAppId
    msaAppTenantId: 'common'
    publicNetworkAccess: 'Enabled'
  }
}

output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output botServiceName string = botService.name
