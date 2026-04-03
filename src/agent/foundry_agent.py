import logging

from openai import AsyncOpenAI


logger = logging.getLogger(__name__)


class FoundryAgent:
    def __init__(self, endpoint: str, model_id: str, api_key: str, system_prompt: str) -> None:
        self._model_id = model_id
        self._system_prompt = system_prompt
        self._client = AsyncOpenAI(base_url=endpoint, api_key=api_key)

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
