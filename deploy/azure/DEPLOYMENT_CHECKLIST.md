# Agent Reach Azure deployment checklist

Target: TE-IT-Dev subscription, UK South, dedicated resource group rg-te-agent-reach-dev.
Status: code staged; not deployed or live-tested.

## Current implementation
- MCP streamable HTTP endpoint: /mcp/
- Health endpoint: /healthz
- Public-only search channels: github (github-api), youtube (yt-dlp), web (public-web)
- Entra JWT validation: issuer, signature, audience, expiry and AgentReach.Invoke delegated scope
- No authenticated channels, browser sessions, cookies or user credentials

## Required configuration
ENTRA_TENANT_ID: Entra tenant GUID
ENTRA_AUDIENCE: exact audience of the API application registration
ENTRA_REQUIRED_SCOPE: AgentReach.Invoke

## Deployment gates
1. Register an Entra API application, configure delegated scope and restrict client/user assignment.
2. Build and scan the Docker image; run security tests and public search smoke tests.
3. Provision isolated Azure Container Apps resources, identity, container registry and monitoring.
4. Configure secure HTTPS ingress, request limits and appropriate outbound restrictions.
5. Validate MCP handshake and tool discovery with a valid token; reject missing, expired and wrong-audience tokens.
6. Confirm ChatGPT MCP OAuth support and complete the account-side connection.

Do not deploy the image publicly or claim ChatGPT connectivity until the above checks succeed.
