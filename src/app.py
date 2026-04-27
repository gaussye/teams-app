import logging

from aiohttp import web
from botbuilder.core import BotFrameworkAdapterSettings, TurnContext
from botbuilder.integration.aiohttp import BotFrameworkHttpAdapter, aiohttp_error_middleware
from botbuilder.schema import Activity

from agent.foundry_agent import FoundryAgent
from bot import TeamsAgentBot
from config import config


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)


adapter_settings = BotFrameworkAdapterSettings(
    config.bot_app_id,
    config.bot_app_password,
    channel_auth_tenant=config.bot_app_tenant_id or None,
)
adapter = BotFrameworkHttpAdapter(adapter_settings)

agent = FoundryAgent(
    endpoint=config.foundry_endpoint,
    model_id=config.foundry_model_id,
    system_prompt=config.system_prompt,
    auth_mode=config.foundry_auth_mode,
    api_key=config.foundry_api_key,
    api_version=config.foundry_api_version,
    entra_scope=config.foundry_entra_scope,
    managed_identity_client_id=config.foundry_managed_identity_client_id,
)
bot = TeamsAgentBot(agent)


async def on_error(context: TurnContext, error: Exception):
    await context.send_activity("The bot encountered an error.")


adapter.on_turn_error = on_error


async def messages(req: web.Request) -> web.Response:
    if "application/json" not in req.headers.get("Content-Type", ""):
        return web.Response(status=415, text="Content-Type must be application/json")

    body = await req.json()
    activity = Activity().deserialize(body)
    auth_header = req.headers.get("Authorization", "")

    response = await adapter.process_activity(activity, auth_header, bot.on_turn)
    if response:
        return web.json_response(data=response.body, status=response.status)

    return web.Response(status=201)


app = web.Application(middlewares=[aiohttp_error_middleware])
app.router.add_post("/api/messages", messages)


if __name__ == "__main__":
    web.run_app(app, host="0.0.0.0", port=3978)
