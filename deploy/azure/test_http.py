"""Exercise the actual ASGI boundary without Azure credentials or network access."""
import os
import sys
from pathlib import Path

os.environ.setdefault("ENTRA_TENANT_ID", "3a07e7f7-d736-4d31-a7bf-bf47df341892")
os.environ.setdefault("ENTRA_AUDIENCE", "api://agent-reach-test")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from starlette.testclient import TestClient
from server import app


def test_health_is_accessible_without_credentials():
    with TestClient(app) as client:
        response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_mcp_is_not_accessible_anonymously():
    with TestClient(app) as client:
        for path in ("/mcp", "/mcp/"):
            response = client.post(path, json={
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": {"protocolVersion": "2025-03-26", "capabilities": {},
                           "clientInfo": {"name": "test", "version": "1.0"}},
            })
            assert response.status_code == 401
            assert response.headers["www-authenticate"].startswith("Bearer ")


def test_mcp_rejects_malformed_token():
    with TestClient(app) as client:
        response = client.post("/mcp/", headers={"Authorization": "Bearer invalid"},
                               json={"jsonrpc": "2.0", "id": 1, "method": "ping"})
    assert response.status_code == 401
