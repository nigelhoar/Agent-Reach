"""Public-only Agent Reach MCP adapter.

IMPORTANT: This application does not authenticate callers.
Deploy only behind an ingress that validates Entra OAuth tokens, blocks bypass,
and forwards authenticated requests. Never expose the container directly.
"""
import asyncio
import os
from mcp.server.fastmcp import FastMCP

# Explicitly enumerated actions; do not expose arbitrary CLI commands.
ACTIONS = {
    "github": {"search"},
    "youtube": {"search"},
    "web": {"search"},
    "v2ex": {"search"},
    "bilibili": {"search"},
}
mcp = FastMCP("Agent Reach public research", host="0.0.0.0", port=8080, stateless_http=True, json_response=True)

@mcp.tool()
async def public_search(channel: str, query: str) -> str:
    """Search one of the approved public channels without a login."""
    if channel not in ACTIONS or "search" not in ACTIONS[channel]:
        raise ValueError("Channel disabled")
    if not query or len(query) > 500:
        raise ValueError("Query must contain 1 to 500 characters")
    proc = await asyncio.create_subprocess_exec(
        "agent-reach", channel, "search", query,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=30)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.communicate()
        raise ValueError("Research timed out")
    if proc.returncode:
        raise ValueError("Research failed")
    return out.decode(errors="replace")[:20000]

if __name__ == "__main__":
    # This flag is a deployment safeguard, NOT authentication.
    if os.getenv("AGENT_REACH_INGRESS_AUTHENTICATED") != "true":
        raise SystemExit("Authenticated ingress must be independently verified")
    mcp.run(transport="streamable-http")
