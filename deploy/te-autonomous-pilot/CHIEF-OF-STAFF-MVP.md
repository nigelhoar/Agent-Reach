# Development Chief of Staff — first usable milestone

The pilot is not complete when autonomous coding passes a benchmark. The product is an always-on **Chief of Staff** that converts the owner's outcomes and priorities into coordinated, bounded work, without requiring the owner to operate an agent dashboard.

## Required behavior

1. **Receive intent through ChatGPT:** "Move project X toward a usable demonstration", "Prioritise these outcomes", "What needs my decision?" ChatGPT should act as the owner's normal interface. The Chief of Staff should be callable through a connected, authenticated interface where supported, not require a new manual dashboard.
2. **Maintain an agenda:** project goals, priority, success criteria, workstream dependencies, budget ceilings, last activity, blockers, status and next action. The operational state must remain private, not in this public repository.
3. **Delegate:** break approved goals into scoped coding, testing, troubleshooting or research tasks. Dispatch to restricted Codex workers using per-task worktrees. ORCH is a candidate scheduler; do not use its unrestricted Codex adapter without a safe wrapper.
4. **Continue without supervision:** pull the next eligible task, validate the work, retry safe transient failures within a small budget, update progress and stop at a real decision or exhausted allowance. Never repeatedly re-run the same task because of a restart.
5. **Deliver results, not just logs:** working development changes, clear test evidence, PRs, task status, decisions needed and next steps. For routine, low-risk development changes, an approved policy may permit automatic merge to development and deployment to staging; production, security boundaries, credentials, identities and data-destructive changes require explicit approval.
6. **Report proactively:** concise consolidated progress and exception report, not a separate dashboard the owner must watch.
7. **Manage expense:** restrict concurrency, time, subscription usage and task count. Stop when allowance is exhausted. ChatGPT subscription login must not silently fall back to an API key.

## First milestone acceptance test

Starting from one owner instruction submitted through ChatGPT:
- Save a private goal and three prioritized tasks with distinct stable IDs.
- Delegate an isolated task to subscription-authenticated Codex.
- Observe its completion and independently verify its tests.
- Record tokens and elapsed time, publish a GitHub draft PR for review, and update the goal's state.
- Without owner prompting, select and dispatch the next task only if budget, dependency and repository policy permit it.
- Provide one consolidated summary and identify decisions needing approval.
- Survive a restarted controller without dispatching duplicate work.

## Deployment approach

Build on the existing isolated VM, Codex CLI subscription login and GitHub connectivity. Keep the controller behind authenticated access. Initially use one concurrent non-production worker and a small set of explicitly allowlisted repositories.

The Chief of Staff is the **control plane**. Codex is the **execution engine**. Agent of Empires is an optional session visibility tool. ORCH is a possible task supervisor, not by itself the Chief of Staff.

**Status: architecture/acceptance criteria recorded; Chief of Staff controller not yet deployed.**
