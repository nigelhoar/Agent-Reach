"""Public-only Agent Reach MCP endpoint with Entra JWT verification."""
import asyncio
import json
import os
from contextlib import asynccontextmanager
from starlette.applications import Starlette
from starlette.responses import JSONResponse, Response
from starlette.routing import Mount, Route
from starlette.types import ASGIApp, Receive, Scope, Send
from mcp.server.fastmcp import FastMCP
from auth import verify

CHANNELS = frozenset({"github", "youtube", "web", "v2ex", "bilibili"})
mcp = FastMCP("Agent Reach public research", stateless_http=True, json_response=True, streamable_http_path="/")

@mcp.tool()
async def public_search(channel: str, query: str) -> dict:
    """Search a public channel without login credentials."""
    if channel not in CHANNELS:
        raise ValueError("Channel disabled")
    if not query or len(query) > 500:
        raise ValueError("Query must be 1-500 characters")
    process = await asyncio.create_subprocess_exec(
        "agent-reach", channel, "search", query, "--backend", "public-web",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, _ = await asyncio.wait_for(process.communicate(), timeout=30)
    except asyncio.TimeoutError:
        process.kill()
        await process.communicate()
        raise ValueError("Research timed out")
    if process.returncode:
        raise ValueError("Public research failed")
    try:
        payload = json.loads(out)
    except (ValueError, UnicodeDecodeError):
        raise ValueError("Invalid upstream response")
    if not payload.get("ok"):
        return {"ok": False, "error": payload.get("error", {}).get("code", "upstream_failure")}
    return {"ok": True, "result": payload.get("result")}

class BearerGate:
    def __init__(self, app: ASGIApp):
        self.app = app
    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] != "http" or scope["path"] == "/healthz":
            return await self.app(scope, receive, send)
        headers = dict(scope.get("headers", []))
        try:
            verify(headers.get(b"authorization", b"").decode("ascii"))
        except Exception:
            response = Response("Unauthorized", status_code=401, headers={"WWW-Authenticate": 'Bearer error="invalid_token"'})
            return await response(scope, receive, send)
        return await self.app(scope, receive, send)

async def health(_):
    return JSONResponse({"status": "ok"})

@asynccontextmanager
async def lifespan(_):
    async with mcp.session_manager.run():
        yield

app = BearerGate(Starlette(routes=[Route("/healthz", health), Mount("/mcp", app=mcp.streamable_http_app())], lifespan=lifespan))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, proxy_headers=False)
