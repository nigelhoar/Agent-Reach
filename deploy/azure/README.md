# Agent Reach Azure deployment (staging)

This directory contains a **non-deployed** MCP bridge and container recipe. It is deliberately fail-closed.

## Architecture
- Dedicated resource group in TE-IT-Dev, UK South.
- Azure Container Apps with ingress restricted until Entra OAuth / validated token gateway is implemented.
- Container image built from this fork, non-root user.
- Public channels only: github, youtube, web, v2ex, bilibili.
- No Chrome session import, login channels, cookies or credentials.
- MCP endpoint: /mcp (FastMCP streamable HTTP).

## Security prerequisites before deployment
1. Implement and test Entra OAuth token validation for ChatGPT MCP clients, including issuer, audience, signature and scopes. Do not expose the service publicly merely by setting AGENT_REACH_INGRESS_AUTHENTICATED.
2. Configure Azure Container Apps authenticated ingress or a trusted reverse proxy; ensure no direct bypass to the container.
3. Pin dependency versions and scan the image. Review third-party subprocess/network behaviour.
4. Apply egress policy, rate limits, request logging without sensitive query contents, and resource quotas.
5. Confirm ChatGPT custom MCP app/connector support and OAuth compatibility in the user's account.
6. Run channel smoke tests; some tools require extra system dependencies.

## Local image build
```sh
docker build -f deploy/azure/Dockerfile -t agent-reach-mcp:dev .
```

Do not deploy or expose this image until authentication prerequisites are complete.
