import os
from dataclasses import dataclass

from dotenv import load_dotenv


load_dotenv()


@dataclass
class AppConfig:
    bot_app_id: str
    bot_app_password: str
    bot_app_tenant_id: str
    foundry_endpoint: str
    foundry_model_id: str
    foundry_api_key: str
    system_prompt: str



def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


config = AppConfig(
    bot_app_id=_required_env("BOT_APP_ID"),
    bot_app_password=_required_env("BOT_APP_PASSWORD"),
    bot_app_tenant_id=os.getenv("BOT_APP_TENANT_ID", "").strip(),
    foundry_endpoint=_required_env("FOUNDRY_ENDPOINT"),
    foundry_model_id=_required_env("FOUNDRY_MODEL_ID"),
    foundry_api_key=_required_env("FOUNDRY_API_KEY"),
    system_prompt=os.getenv("SYSTEM_PROMPT", "You are a helpful Teams assistant.").strip(),
)
