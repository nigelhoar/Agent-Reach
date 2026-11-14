"""Security regression tests for the Azure MCP bridge."""
import importlib.util
import os
import sys
from pathlib import Path
from unittest.mock import patch
import pytest
import jwt

HERE = Path(__file__).resolve().parent
os.environ.setdefault("ENTRA_TENANT_ID", "3a07e7f7-d736-4d31-a7bf-bf47df341892")
os.environ.setdefault("ENTRA_AUDIENCE", "api://agent-reach-test")
sys.path.insert(0, str(HERE))

from auth import verify

def test_missing_bearer_token_rejected():
    with pytest.raises(ValueError, match="Bearer"):
        verify("")

def test_oversized_token_rejected():
    with pytest.raises(ValueError, match="Invalid"):
        verify("Bearer " + "x" * 17000)

def test_unsigned_token_rejected():
    token = jwt.encode({"aud": "api://agent-reach-test"}, key="", algorithm="none")
    with pytest.raises(Exception):
        verify("Bearer " + token)

def test_wrong_scope_rejected():
    from auth import SCOPE
    assert SCOPE == "AgentReach.Invoke"

def test_public_channels_only():
    from server import CHANNELS
    assert {"instagram", "linkedin", "reddit", "xiaohongshu", "x", "facebook"}.isdisjoint(CHANNELS)
    assert CHANNELS == {"github", "youtube", "web"}
    from server import BACKENDS
    assert BACKENDS["web"] == ("--backend", "public-web")
    assert BACKENDS["github"] == ("--backend", "github-api")
    assert BACKENDS["youtube"] == ()
