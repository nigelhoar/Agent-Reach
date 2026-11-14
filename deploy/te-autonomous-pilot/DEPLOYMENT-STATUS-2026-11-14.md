# Development Chief of Staff: deployment milestone

**Verified from Azure VM RunCommand terminal output on 14 November 2026.**
Scope: isolated TE-IT-Dev pilot VM only; Paperclip service and local project-intelligence tests. This document is an operational checklist, not a claim that the autonomous Chief of Staff is production-ready.

## Verified running

- VM: `vm-te-agent-reach-dev` (UK South), unprivileged `tepilot` user.
- Paperclip: managed version `2026.1106.0`.
- Node.js for Paperclip: `v24.22.3`, installed alongside the existing Node 22/Codex runtime.
- Service: `te-paperclip-cos.service` active; survives VM restart through systemd.
- React UI/API: `127.0.0.1:3100`, health endpoint returns success.
- Binding: private loopback listener verified; no Cloudflare changes.
- Config: `authenticated/private`, `/home/tepilot/paperclip-cos/instances/default/config.json`.
- Embedded database and local storage passed Paperclip doctor checks.
- Codex CLI login: `Logged in using ChatGPT`.
- Local project intelligence: `reconcile-evidence.mjs`, four regression tests passed (4/4).
- Pilot IMDS deny for `tepilot` was checked.

## Not yet complete

1. **Administrator bootstrap**: verify a human administrator has claimed the initial Paperclip authenticated instance. Invite URLs are secrets; do not copy them into GitHub, messages, logs or public URLs.
2. **Secure mobile access**: no externally reachable UI yet. Assess corporate Azure/Entra reverse-proxy or authenticated private-access route without changing Cloudflare. VM has no public IP, and the frontend remains bound only to loopback.
3. **Portfolio entity creation**: Paperclip company, goals, projects, agents and workspaces must be created before dispatch.
4. **Project intelligence ingest**: current reconciler is a local, test-passing component, **not** a live connector or integrated Paperclip workflow. Build authorised, provenance-preserving GitHub/Portfolio/ChatGPT decision ingest; store private project content privately, never in this public repository.
5. **Autonomous delivery**: development manager, worker, reviewer, schedule, job permission limits, PR-only policy, test gates and exception escalation not yet activated.
6. **Agent safety and usage**: set per-task time budgets, concurrency 1 initially, verified sandbox behavior, no prod writes/secrets, monitored ChatGPT subscription capacity, explicit human approvals.
7. **Resilience**: verify database backup and restore, service restart, recovery from incomplete jobs.

## Immediate acceptance test

From a securely authenticated browser, create a test company, three real portfolio projects and one scoped objective; the Chief of Staff should reconcile evidence, select an eligible low-risk development ticket, run isolated Codex with subscription auth, test code, produce a PR, and only notify the owner for material blockers or decisions.

**Do not describe Paperclip as autonomous, connected to ChatGPT Projects, externally accessible or production-capable until those capabilities are separately demonstrated.**
