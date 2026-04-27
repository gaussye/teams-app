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
    foundry_auth_mode: str
    foundry_api_key: str
    foundry_api_version: str
    foundry_entra_scope: str
    foundry_managed_identity_client_id: str
    system_prompt: str



def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def _optional_env(name: str) -> str:
    return os.getenv(name, "").strip()


config = AppConfig(
    bot_app_id=_required_env("BOT_APP_ID"),
    bot_app_password=_required_env("BOT_APP_PASSWORD"),
    bot_app_tenant_id=_optional_env("BOT_APP_TENANT_ID"),
    foundry_endpoint=_required_env("FOUNDRY_ENDPOINT"),
    foundry_model_id=_required_env("FOUNDRY_MODEL_ID"),
    foundry_auth_mode=_optional_env("FOUNDRY_AUTH_MODE").lower() or "entra",
    foundry_api_key=_optional_env("FOUNDRY_API_KEY"),
    foundry_api_version=_optional_env("FOUNDRY_API_VERSION") or "2024-10-21",
    foundry_entra_scope=_optional_env("FOUNDRY_ENTRA_SCOPE") or "https://cognitiveservices.azure.com/.default",
    foundry_managed_identity_client_id=_optional_env("FOUNDRY_MANAGED_IDENTITY_CLIENT_ID"),
    system_prompt=_optional_env("SYSTEM_PROMPT") or "You are a helpful Teams assistant.",
)

if config.foundry_auth_mode not in {"entra", "api-key"}:
    raise ValueError("FOUNDRY_AUTH_MODE must be either 'entra' or 'api-key'")

if config.foundry_auth_mode == "api-key" and not config.foundry_api_key:
    raise ValueError("FOUNDRY_API_KEY is required when FOUNDRY_AUTH_MODE=api-key")
