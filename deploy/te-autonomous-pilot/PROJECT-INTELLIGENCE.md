# Project intelligence: living objectives, not stale status fields

**Status:** implementation contract for Taylor Emmet Development Chief of Staff (Paperclip). Store operational data privately on the Azure VM/Paperclip database. This source-controlled document defines generic behavior; it contains no imported internal project records or ChatGPT transcripts.

## Core principle

**No single existing system is the canonical statement of what a project now aims to achieve.** A project changes direction over time. The Chief of Staff must reconcile:

1. **Explicit owner decisions** made in current and prior ChatGPT conversations: requirements, revised scope, deliberate exclusions and priorities.
2. **GitHub reality:** repository structure, current branch/merged commits, PRs, tests, workflow runs, releases, and open issues. Distinguish proposed code (PR) from merged, deployed and independently verified code.
3. **Taylor Emmet Operations Portfolio:** project identity, business ownership, strategic programme context, dependencies, milestones and delegated workstreams. Treat summaries and percentage complete as potentially stale.
4. **Evidence from the running application and CI:** if a claimed feature is live, seek a deployment/health/smoke-test proof; otherwise say "source implemented" or "verification pending".

ChatGPT project conversations are **not automatically available to the Azure VM**. Do not imply that Paperclip can scrape private conversations or that the ChatGPT Space API represents ChatGPT Projects. Add an explicit consented chat decision import/sync mechanism, or have ChatGPT itself publish structured decision events through an authenticated, access-controlled endpoint when a relevant decision is made. Historical conversations may initially be summarised here, reviewed by the user, and imported as private evidence snapshots; do not silently ingest full conversations into GitHub.

## Canonical project registry (private)

An entry is a durable logical project, not necessarily one repository or one Portfolio record:

- \`project_key\` — stable slug.
- \`display_name\` and \`aliases\` — allow renaming.
- \`portfolio_ids\` — zero or more Taylor Emmet Project Tracker ids.
- \`github_repositories\` — zero or more allowlisted \`owner/repo\` identities and relevant branches.
- \`chat_sources\` — explicit, authorised decisions/intelligence captures from ChatGPT.
- \`owners\`, \`stakeholders\`, \`priority\`, \`relationships\` — controlled identifiers.
- \`policy\` — permitted development operations and escalation gates.

No fuzzy auto-merging of similar names across different legal/business contexts. Start from human-reviewed mappings; show unknown relationships as "unlinked".

## Project event/evidence model

Each ingested item carries provenance, time and what it actually proves:

\`\`\`json
{
  "event_id": "github-pr:owner/repo#123",
  "project_key": "example-project",
  "source": "chatgpt_decision",
  "source_ref": "private-reference-or-linked-url",
  "occurred_at": "2026-11-14T20:15:00Z",
  "observed_at": "2026-11-14T22:05:00Z",
  "kind": "decision",
  "authority": "user_explicit",
  "summary": "The approved change, not a raw transcript",
  "scope_additions": ["A clearly approved capability"],
  "scope_removals": ["The superseded approach"],
  "supersedes_event_ids": [],
  "verified": false,
  "confidence": "high"
}
\`\`\`

Allowed \`kind\`: \`proposal\`, \`decision\`, \`scope_change\`, \`status\`, \`implementation\`, \`verification\`, \`failure\`, \`blocker\`, \`correction\`, \`priority_change\`. \`authority\`: \`user_explicit\`, \`business_owner\`, \`github_evidence\`, \`portfolio_record\`, \`agent_inference\`. Timestamps are both event time and capture time to handle late-arriving evidence.

**Do not promote** an AI inference, GitHub issue title, old Tracker target, experimental branch or a casual discussion to a binding owner decision.

## Living Brief output

Maintain one versioned, evidence-linked brief per project:

- **Current objective:** what success means *now*, in business terms.
- **Accepted scope and explicit non-goals** (including what was superseded and why).
- **Current implementation position:** evidenced by tests, merged code, deployment/release, and live app verification separately.
- **Next smallest useful outcome** and the evidence required to mark it complete.
- **Dependencies, priorities and permitted autonomy**.
- **Unresolved contradictions** and their materiality.
- **Last evidence refresh and confidence**.
- **Decision history and source references**.
- **Chief of Staff action**: start, keep working, verify, defer, or escalate.

Avoid fabricated percentage-complete scores. Distinguish "approved in conversation", "implemented in PR", "merged", "deployed", "functionally verified". Record changes as revisions rather than overwriting prior decisions without explanation.

## Reconciliation rules

1. A later **explicit** owner decision supersedes an older owner decision only if it concerns the *same aspect* of scope. Record both and the replacement relationship; do not simply use the newest timestamp from any source.
2. A GitHub merge or deployed build demonstrates implementation but does not redefine the business objective.
3. A newer GitHub issue may reflect a changed requirement, but until its authorisation is clear label it \`proposed\`/ \`planned\`, not definitively decided.
4. Portfolio records supply identity, owners and organisational dependencies, but stale/contradictory summaries cannot override accepted revisions.
5. User statements such as "this chat is ONLY about Post-Completion" are source-boundary controls; information copied accidentally between conversations must not contaminate projects.
6. Preserve explicit exclusions, especially read-only probes, no MatterSphere write, no client-data exposure, no production deployments, no secret access.
7. When sources conflict, record the precise conflicting claims and dates. Escalate only if the conflict blocks a meaningful next step or carries material risk; otherwise continue with safe, nondependent work.
8. Do not upload internal Tracker records or ChatGPT conversation extracts to a public GitHub repository. Store in private Paperclip/Azure state with per-source permissions, retention and audit.

## Refresh and autonomy

- Ingest GitHub PRs/issues/merged changes/check runs **incrementally**, using a token stored as a secret and least privilege.
- Refresh the Tracker through the **authenticated Project Tracker MCP** on a cadence, respecting per-user/department visibility; a service identity's permission is not automatically that of Nigel.
- Capture new ChatGPT decisions explicitly as events. Historical imports need reviewable source mapping; no silently implied access to all ChatGPT Projects.
- Refresh Living Brief on new evidence and on a periodic scheduled run; deduplicate by source + immutable source id/revision. Keep every revision and evidence link.
- Classify candidate next tasks: \`can_execute\`, \`needs_access\`, \`needs_decision\`, \`needs_prod_approval\`, \`outside_scope\`.
- Delegate **only** \`can_execute\` tasks to an isolated coding worker using per-task worktrees and test evidence, never directly from untrusted source text.

## "Needs Nigel" policy

Escalate when a real choice is unavoidable: mutually exclusive approved objectives; production or data-destructive change; materially expanded credentials/exposure; purchase or unexpected spend; legal/regulatory/client-data decision; missing permission that cannot be lawfully resolved; budget exhaustion; unrecoverable failure after bounded retries.

Do not interrupt for routine tests, safe PR review prep, re-running permitted CI, a stale descriptive Portfolio field, or alternative implementations within agreed scope. Bundle nonurgent findings into a digest.

## Acceptance test

For each test project present contradictory old Tracker text, a later explicit ChatGPT scope correction, an older open GitHub issue and a newer merged PR. Expected behavior: preserve the current decision as objective; report the PR as implemented only to its verified stage; mark the Tracker stale, retain its organisational metadata, and propose the next missing outcome. Verify an ambiguous decision remains tagged uncertain rather than invented. Verify a restarted ingest doesn't duplicate events. Verify no private source is printed or committed to public GitHub.
