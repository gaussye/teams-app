import logging
import os
from urllib.parse import urlparse

import httpx
from aiohttp import web


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)
logger = logging.getLogger("teams_proxy")


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


UPSTREAM_BASE_URL = _required_env("PROXY_UPSTREAM_BASE_URL").rstrip("/")
UPSTREAM_HOST_HEADER = os.getenv("PROXY_UPSTREAM_HOST_HEADER", "").strip()
REQUEST_TIMEOUT_SECONDS = float(os.getenv("PROXY_TIMEOUT_SECONDS", "60"))


async def messages(req: web.Request) -> web.Response:
    if "application/json" not in req.headers.get("Content-Type", ""):
        return web.Response(status=415, text="Content-Type must be application/json")

    body = await req.read()
    auth_header = req.headers.get("Authorization", "")
    target_url = f"{UPSTREAM_BASE_URL}/api/messages"

    headers = {
        "Content-Type": req.headers.get("Content-Type", "application/json"),
    }
    if UPSTREAM_HOST_HEADER:
        # Optional override for private-IP upstream routing through ACA ingress.
        headers["Host"] = UPSTREAM_HOST_HEADER
    if auth_header:
        headers["Authorization"] = auth_header

    logger.info(
        "Proxy forwarding request. target=%s host_header=%s content_type=%s auth_present=%s",
        target_url,
        headers.get("Host", urlparse(target_url).netloc),
        headers.get("Content-Type", ""),
        bool(auth_header),
    )

    timeout = httpx.Timeout(REQUEST_TIMEOUT_SECONDS)
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            upstream_response = await client.post(target_url, content=body, headers=headers)
        except httpx.HTTPError as exc:
            logger.exception("Failed to proxy request to upstream")
            return web.Response(status=502, text=f"Upstream call failed: {exc}")

    logger.info(
        "Proxy upstream response. target=%s status=%s",
        target_url,
        upstream_response.status_code,
    )

    response_headers = {}
    content_type = upstream_response.headers.get("Content-Type")
    if content_type:
        response_headers["Content-Type"] = content_type

    return web.Response(
        status=upstream_response.status_code,
        body=upstream_response.content,
        headers=response_headers,
    )


async def healthz(_: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


app = web.Application()
app.router.add_get("/healthz", healthz)
app.router.add_post("/api/messages", messages)


if __name__ == "__main__":
    # Azure App Service injects PORT at runtime.
    port = int(os.getenv("PORT", "8000"))
    web.run_app(app, host="0.0.0.0", port=port)