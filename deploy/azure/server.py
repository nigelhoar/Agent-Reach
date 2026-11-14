"""Minimal MCP bridge for public Agent Reach channels.
OAuth / Entra validation must be enforced by a trusted ingress before production use.
"""
import asyncio
import json
import os
from mcp.server.fastmcp import FastMCP

ALLOWED = {"github", "youtube", "web", "v2ex", "bilibili"}
mcp = FastMCP("Agent Reach public research", host="0.0.0.0", port=8080, stateless_http=True, json_response=True)

@mcp.tool()
async def public_research(channel: str, action: str, query: str = "") -> str:
    """Execute a public-channel Agent Reach action; no authenticated channels."""
    if channel not in ALLOWED:
        raise ValueError("Channel disabled: only public research is permitted")
    if not action or not action.replace("-", "").replace("_", "").isalnum():
        raise ValueError("Invalid action")
    if len(query) > 2000:
        raise ValueError("Query too long")
    proc = await asyncio.create_subprocess_exec(
        "agent-reach", channel, action, *([query] if query else []),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=45)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.communicate()
        raise ValueError("Research timed out")
    if proc.returncode:
        raise ValueError("Research failed: " + err.decode(errors="replace")[:400])
    return out.decode(errors="replace")[:30000]

if __name__ == "__main__":
    if os.getenv("AGENT_REACH_INGRESS_AUTHENTICATED") != "true":
        raise SystemExit("Refusing to start without authenticated ingress declaration")
    mcp.run(transport="streamable-http")
