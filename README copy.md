# Teams Calling Bot + Voice Live (Node.js)

## Overview
This project provides a minimal Teams Calling Bot skeleton and a placeholder media bridge to connect Teams audio streams with Azure Voice Live for real-time voice conversations.

## What’s Included
- Basic Express server
- Bot Framework adapter and message endpoint
- Calling endpoints placeholders (`/api/calls`, `/api/callback`)
- Media bridge stubs to integrate Voice Live
- Teams app manifest template with calling capability

## Local Setup
1. Copy `.env.example` to `.env` and fill in values.
2. Install dependencies.
3. Start the server.

## Next Steps
- Implement media streaming with Teams Calling and bridge audio to Voice Live.
- Wire up authentication and certificate for calling callbacks.
- Deploy to Azure Bot Service + App Service.

## Minimal Calling Flow (Placeholder)
1. Incoming call hits `/api/calls`.
2. `CallHandler` starts `VoiceLiveClient` and `MediaBridge`.
3. Implement media stream bridging in `src/calling/media-bridge.js`.

## Debug/Launch
- Run: `npm start`
- Ensure public HTTPS for callbacks when testing calling.

## RAG (Foundry Knowledge Base)
This project supports RAG by querying an Azure AI Search index that backs your Foundry Knowledge Base.

1. Set `RAG_ENABLED=true` in `.env`.
2. Configure search settings:
	- `FOUNDRY_KB_SEARCH_ENDPOINT`
	- `FOUNDRY_KB_SEARCH_API_KEY`
	- `FOUNDRY_KB_SEARCH_INDEX`
3. (Optional) adjust fields and limits:
	- `FOUNDRY_KB_CONTENT_FIELD`, `FOUNDRY_KB_TITLE_FIELD`, `FOUNDRY_KB_URL_FIELD`
	- `RAG_TOP_K`, `RAG_TIMEOUT_MS`

When user speech transcription completes, the server retrieves top documents and injects context into the Voice Live session instructions for the next response.

## Teams SSO（生产部署步骤）

下面步骤是本项目已验证的配置顺序，建议按顺序执行。

### 1) 配置 Microsoft Entra 应用
1. 选择一个 Entra App 作为 Teams Tab 的 SSO 应用（`clientId`）。
2. 在 **Expose an API** 中配置：
	- `identifierUris` 至少包含：
	  - `api://<your-tab-domain>/<clientId>`
	  - （可选兼容）`api://<clientId>`
	- 创建 scope：`access_as_user`
3. 在 `preAuthorizedApplications` 添加 Teams 客户端：
	- `1fec8e78-bce4-4aaf-ab1b-5451cc387264`（Teams Web/Desktop）
	- `5e3ce6c0-2b1f-4285-8d4b-75ee78787346`（Teams Mobile）

### 2) 配置 Teams Manifest
在 `appManifest/manifest.json` 中：
1. `permissions` 包含 `identity`。
2. 配置 `webApplicationInfo`：
	- `id`: `<clientId>`
	- `resource`: `api://<your-tab-domain>/<clientId>`
3. `validDomains` 必须包含你的 Tab 域名（与 `contentUrl` 同域）。
4. 每次上传新包前递增 `version`（避免 Teams 缓存旧 manifest）。

### 3) 配置服务端环境变量
在 `.env`（以及生产环境变量）中：
- `TEAMS_SSO_ENABLED=true`
- `TEAMS_TENANT_ID=<tenant-id>`
- `TEAMS_SSO_CLIENT_ID=<clientId>`
- `TEAMS_SSO_ALLOWED_AUDIENCES=<clientId>,api://<your-tab-domain>/<clientId>,api://<clientId>`

说明：本项目后端会校验 JWT 的 `iss` 和 `aud`。实测 Teams 返回的 `aud` 可能是纯 `clientId`，也可能是 `api://...`，所以建议三种都加到允许列表。

### 4) 发布与生效
1. 部署后端（镜像或代码）。
2. 更新 Container App 环境变量并等待新 revision Ready。
3. 重新打包 `voicelive-app.zip`（包含 `manifest.json` + 两个图标）。
4. 在 Teams 中卸载旧应用并上传新 zip。

### 5) 验证与排错
如果看到 `Teams authentication failed`，优先检查：
1. `webApplicationInfo.resource` 是否与 Tab iframe 域名一致。
2. Entra `identifierUris` 是否包含相同 resource。
3. 后端 `TEAMS_SSO_ALLOWED_AUDIENCES` 是否包含 token 的 `aud`。
4. 日志中是否出现：
	- 前端：`[VoiceLive][AUTH]`
	- 后端：`[WS] Unauthorized connection rejected`
	- 验签详情：`Teams token validation failed: {... tokenAud ... expectedAudience ...}`

常见错误对照：
- `App resource defined in manifest and iframe origin do not match`
  - 处理：将 manifest 的 `webApplicationInfo.resource` 改成 `api://<your-tab-domain>/<clientId>`。
- `unexpected "aud" claim value`
  - 处理：把日志里的 `tokenAud` 加入 `TEAMS_SSO_ALLOWED_AUDIENCES`。
