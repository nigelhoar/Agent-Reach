#!/usr/bin/env bash
# Install and locally verify the read-only Agent Reach MCP service.
# Run as root on vm-te-agent-reach-dev via Azure VM Run Command.
set -euo pipefail
ROOT=/opt/agent-reach
SOURCE="$ROOT/source"
BRANCH="feature/read-only-chatgpt-mcp"
test -x "$ROOT/venv/bin/agent-reach" || { echo "ERROR: Agent Reach CLI not installed"; exit 1; }
test -d "$SOURCE/.git" || { echo "ERROR: Source checkout missing"; exit 1; }
git -C "$SOURCE" fetch origin "$BRANCH"
git -C "$SOURCE" checkout -B "$BRANCH" "origin/$BRANCH"
python3 -m venv "$ROOT/mcp-venv"
"$ROOT/mcp-venv/bin/python" -m pip install --disable-pip-version-check 'mcp>=1.8,<2'
"$ROOT/mcp-venv/bin/python" -m py_compile "$SOURCE/deploy/te-readonly-mcp/server.py"
echo "=== Public Agent Reach search smoke test ==="
"$ROOT/venv/bin/agent-reach" github search "openai codex" --limit 2 | python3 -c 'import json,sys;x=json.load(sys.stdin);print("Agent Reach github search OK:",x.get("ok"));print(str(x.get("error"))[:400]);sys.exit(0 if x.get("ok") else 1)'
echo "=== MCP tool registration test ==="
PYTHONPATH="$SOURCE/deploy/te-readonly-mcp" "$ROOT/mcp-venv/bin/python" -c 'import server; print("MCP import: OK; server name: "+server.mcp.name)'
echo "Ready for Secure MCP Tunnel configuration (stdio)."
