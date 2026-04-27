import logging
from urllib.parse import urlparse

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI, AsyncOpenAI


logger = logging.getLogger(__name__)


class FoundryAgent:
    def __init__(
        self,
        endpoint: str,
        model_id: str,
        system_prompt: str,
        auth_mode: str,
        api_key: str = "",
        api_version: str = "2024-10-21",
        entra_scope: str = "https://cognitiveservices.azure.com/.default",
        managed_identity_client_id: str = "",
    ) -> None:
        self._model_id = model_id
        self._system_prompt = system_prompt
        client_kind = "openai"
        if auth_mode == "entra":
            credential_kwargs = {}
            if managed_identity_client_id:
                credential_kwargs["managed_identity_client_id"] = managed_identity_client_id
            credential = DefaultAzureCredential(**credential_kwargs)
            token_provider = get_bearer_token_provider(credential, entra_scope)
            azure_endpoint = self._normalize_azure_endpoint(endpoint)
            self._client = AsyncAzureOpenAI(
                azure_endpoint=azure_endpoint,
                azure_ad_token_provider=token_provider,
                api_version=api_version,
            )
            client_kind = "azure-entra"
        else:
            self._client = AsyncOpenAI(base_url=endpoint, api_key=api_key)
            client_kind = "openai-api-key"

        logger.info(
            "Foundry client initialized. auth_mode=%s endpoint=%s api_version=%s client=%s",
            auth_mode,
            endpoint,
            api_version,
            client_kind,
        )

    @staticmethod
    def _normalize_azure_endpoint(endpoint: str) -> str:
        # AsyncAzureOpenAI expects the resource endpoint (https://<resource>.openai.azure.com)
        parsed = urlparse(endpoint)
        if not parsed.scheme or not parsed.netloc:
            return endpoint.rstrip("/")
        return f"{parsed.scheme}://{parsed.netloc}"

    async def generate_reply(self, user_input: str) -> str:
        logger.info("Foundry request started. model=%s input_len=%d", self._model_id, len(user_input or ""))
        try:
            completion = await self._client.chat.completions.create(
                model=self._model_id,
                temperature=0.2,
                messages=[
                    {"role": "system", "content": self._system_prompt},
                    {"role": "user", "content": user_input},
                ],
            )
        except Exception:
            logger.exception("Foundry request failed. model=%s", self._model_id)
            raise

        content = completion.choices[0].message.content
        reply = (content or "").strip() or "I could not generate an answer for that request."
        logger.info(
            "Foundry response received. model=%s completion_id=%s output_len=%d output=%s",
            self._model_id,
            getattr(completion, "id", ""),
            len(reply),
            reply,
        )
        return reply
