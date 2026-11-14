# Agent Reach deployment activation

The workflow in `.github/workflows/agent-reach-azure-dev.yml` is manual and fail-closed. It will not deploy until dedicated infrastructure and GitHub environment variables exist.

## Required Azure resources
Subscription: TE-IT-Dev (376a6b21-3fa4-493d-91ac-ba160a0324cd)
Location: UK South
Resource group: rg-te-agent-reach-dev
Dedicated Azure Container Registry, Container Apps environment, and Container App with **external ingress disabled**.
The Container App must use a user-assigned managed identity with AcrPull on the dedicated registry. Its Entra settings must be provided securely, and it must have functioning access to the container registry.

Create a dedicated deployment user-assigned managed identity in a separate identity resource group, not an application identity. Give it only the roles needed for image build and Container App update within the Agent Reach resource group and registry. Add federated identity credential:
- Issuer: https://token.actions.githubusercontent.com
- Subject: repo:nigelhoar/Agent-Reach:environment:development
- Audience: api://AzureADTokenExchange

## GitHub environment
Create GitHub environment `development` and require a reviewer where supported. Configure environment variables:
- AGENT_REACH_AZURE_CLIENT_ID: dedicated deployment identity client ID
- AGENT_REACH_AZURE_TENANT_ID: 3a07e7f7-d736-4d31-a7bf-bf47df341892
- AGENT_REACH_AZURE_SUBSCRIPTION_ID: 376a6b21-3fa4-493d-91ac-ba160a0324cd
- AGENT_REACH_RESOURCE_GROUP: rg-te-agent-reach-dev
- AGENT_REACH_ACR_NAME: dedicated registry name
- AGENT_REACH_APP_NAME: dedicated Container App name

Set repository variable `AGENT_REACH_DEPLOY_ENABLED=true` **only after** the infrastructure and auth checks have passed. Run workflow manually in GitHub Actions.

## Important limitations
- This workflow deploys to **existing** infrastructure; it deliberately does not provision Azure resources or change network exposure.
- The current bridge is not production-tested; verify Python dependencies, GitHub/YouTube/web backends, bearer-token rejection, MCP handshake and actual OAuth compatibility before exposing it.
- An externally reachable ChatGPT MCP endpoint will eventually be necessary. Configure a controlled authenticated ingress separately, after tests. The current workflow deliberately refuses external ingress.
- Do not reuse the reception application's deployment identity or grant subscription-wide Contributor access.
