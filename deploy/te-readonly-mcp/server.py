"""Read-only Agent Reach MCP bridge for a private OpenAI Secure MCP Tunnel.

Runs over stdio only. No HTTP listener, credentials or authenticated channels.
"""
from __future__ import annotations

import ipaddress
import json
import os
import subprocess
from urllib.parse import urlsplit

from mcp.server.fastmcp import FastMCP

CLI = os.environ.get("AGENT_REACH_CLI", "/opt/agent-reach/venv/bin/agent-reach")
mcp = FastMCP("Taylor Emmet Agent Reach (public read-only)")


def _run(*args: str, timeout: int = 50) -> dict:
    """Never invoke a shell or permit arbitrary Agent Reach management actions."""
    try:
        proc = subprocess.run(
            [CLI, *args],
            shell=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            env={**os.environ, "PYTHONUNBUFFERED": "1"},
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "Upstream request exceeded time budget"}
    except OSError as exc:
        return {"ok": False, "error": f"Agent Reach executable unavailable: {type(exc).__name__}"}
    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"ok": False, "error": "Agent Reach returned an invalid response"}
    if not isinstance(result, dict):
        return {"ok": False, "error": "Unexpected Agent Reach response"}
    if proc.returncode and result.get("ok"):
        result["ok"] = False
    # Limit content flowing through MCP (large pages and transcripts are truncated).
    payload = json.dumps(result, ensure_ascii=False)
    if len(payload) > 55000:
        return {"ok": bool(result.get("ok")), "truncated": True, "content": payload[:55000]}
    return result


def _query(value: str) -> str:
    value = value.strip()
    if not 2 <= len(value) <= 300:
        raise ValueError("Query must contain 2 to 300 characters")
    return value


def _public_url(value: str) -> str:
    value = value.strip()
    if len(value) > 2000:
        raise ValueError("URL too long")
    parsed = urlsplit(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Only public HTTPS URLs without embedded credentials are allowed")
    host = parsed.hostname.lower().rstrip(".")
    if host == "localhost" or host.endswith((".local", ".internal", ".localhost")):
        raise ValueError("Private hostname rejected")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        if not address.is_global:
            raise ValueError("Non-public IP rejected")
    return value


@mcp.tool()
def search_web(query: str, limit: int = 5) -> dict:
    """Search public web pages with Agent Reach/Exa; returns sources and excerpts."""
    return _run("web", "search", _query(query), "--limit", str(max(1, min(limit, 8))))


@mcp.tool()
def read_webpage(url: str) -> dict:
    """Read a publicly accessible HTTPS page as cleaned text; never use with internal URLs."""
    return _run("web", "read", _public_url(url))


@mcp.tool()
def search_youtube(query: str, limit: int = 5) -> dict:
    """Find public YouTube videos without logging into a user account."""
    return _run("youtube", "search", _query(query), "--limit", str(max(1, min(limit, 8))))


@mcp.tool()
def youtube_video(url: str) -> dict:
    """Read metadata for a public YouTube video, without downloading media."""
    value = _public_url(url)
    host = urlsplit(value).hostname or ""
    if host not in ("youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"):
        raise ValueError("Only YouTube links are supported")
    return _run("youtube", "read", value)


@mcp.tool()
def search_github(query: str, limit: int = 5) -> dict:
    """Search public GitHub repositories using Agent Reach's public channel."""
    return _run("github", "search", _query(query), "--limit", str(max(1, min(limit, 8))))


@mcp.tool()
def list_channels() -> dict:
    """List supported Agent Reach channels. Only public tools listed here are exposed."""
    result = _run("channels")
    return {"ok": result.get("ok"), "allowed_tools": [
        "search_web", "read_webpage", "search_youtube",
        "youtube_video", "search_github", "list_channels"
    ], "note": "Authenticated channels and management commands are deliberately disabled."}


if __name__ == "__main__":
    mcp.run(transport="stdio")
