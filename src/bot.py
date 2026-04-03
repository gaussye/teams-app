from botbuilder.core import ActivityHandler, MessageFactory, TurnContext

from agent.foundry_agent import FoundryAgent


class TeamsAgentBot(ActivityHandler):
    def __init__(self, agent: FoundryAgent) -> None:
        self._agent = agent

    async def on_message_activity(self, turn_context: TurnContext) -> None:
        user_text = (turn_context.activity.text or "").strip()
        if not user_text:
            await turn_context.send_activity("Please enter a message.")
            return

        try:
            reply_text = await self._agent.generate_reply(user_text)
        except Exception:
            reply_text = "The agent is temporarily unavailable. Please try again later."

        await turn_context.send_activity(MessageFactory.text(reply_text))
