# Subscription-authenticated autonomous coding pilot — benchmark results

**Observed:** 14 November 2026 (UTC). **Status:** three synthetic Python benchmark runs passed.

## Goal
Prove that the existing isolated Azure Linux coding pilot can perform autonomous coding work through Codex authenticated using a ChatGPT subscription, and compare direct Codex execution with ORCH and Agent of Empires (AoE).

## Results

| Measure | Direct Codex | ORCH v1.0.34 + Codex | AoE v1.23.0 + Codex |
| --- | --- | --- | --- |
| Synthetic `unique_tasks` repair | Completed | Completed | Completed |
| Python unit tests | 3/3 PASS | 3/3 PASS | 3/3 PASS |
| Source files modified | 2 | 2 | 2 |
| Diff | +9 / -1 lines | +13 / -1 lines | +20 / -1 lines |
| Reported tokens | 63,037 total (62,490 input, 547 output) | 89,039 in ORCH's agent accounting | Not collected |
| Cached input tokens | 54,656 | Not provided | Not provided |
| Task attempts | One | One | One prompt, after troubleshooting non-coding startup attempts |
| Model's working time | Not measured | Approx. 16 seconds inferred from output timestamps | 19 seconds reported in Codex TUI |
| Operating mode | Headless exec | One assigned ORCH task | One persistent terminal session |
| Completion process | Codex exec exit 0 | ORCH task done, process exit 0 | AoE session stopped after passing tests |

**Interpretation:** All three paths generated correct benchmark code. Do **not** infer comparative cost efficiency from reported tokens: ORCH's counter is not verified as identical to Codex raw JSON usage, model settings were not standardized, and AoE token data were not captured. This is a single simple task per tool, not a reliability or productivity study.

## Verified safeguards and limitations

- The dedicated Linux pilot account owns a mode-600 Codex authentication file, and `codex login status` reported **Logged in using ChatGPT**. No OpenAI API key was used for these test calls.
- The pilot account was checked against the established IMDS egress REJECT rule.
- Direct execution used Codex `workspace-write`; the ORCH adapter's upstream default uses `danger-full-access`, so the comparison used a separate root-owned wrapper that replaces that request with `workspace-write`. **Do not use the upstream ORCH Codex adapter unguarded on real repositories.**
- ORCH task was assigned explicitly with max attempts 1, run under a bounded systemd cgroup, and reported task status `done`.
- AoE's hook approval is installation-wide for the pilot account; Codex then independently requested hook trust. We explicitly selected **Continue without trusting** and captured the successful coding result.
- AoE warned that the native Codex session ID had not been reported; conversation resume is **not verified**. Hooks were skipped, so hook-based activity status is not proven reliable. The benchmark used source/test polling instead.
- AoE session stop was confirmed by the runner after success; the independent systemd stop watchdog was armed but its disconnect/failure behavior has **not** been stress-tested.
- A Codex sandbox request does not by itself prove egress isolation, prevent every filesystem escape, or grant production security approval. The synthetic project contained no client data.
- ChatGPT subscription authentication does not establish the remaining included Codex allowance or a £0 marginal cost. Monitor workspace usage and keep automatic credit reload disabled where required.

## Recommendation

**Adopt a minimal orchestrated worker pattern for the next controlled pilot**, not a full always-on autonomous development service yet:

1. **Codex CLI** is the coding worker, running under the isolated, non-privileged identity with bounded runtime and explicit repository worktrees.
2. **ORCH** is a candidate for task intake, assignment, retries and auditable run state **only after** replacing or securely encapsulating the current unrestricted Codex adapter. Retrying tasks needs explicit policy and budgets.
3. **Agent of Empires** is optional for operator visibility and interactive troubleshooting; do not depend on its resume or hook-based status until measured and repaired.
4. Use a controlled job queue, deduplicated job IDs, repository allowlist, clean branch/worktree per job, automated tests, GitHub PR output, and **human approval for merge/deploy**.
5. Capture comparable per-run telemetry: start/end UTC, model/version, raw Codex token usage, cached tokens, test outcomes, source diff, failure reason, cleanup proof, and subscription allowance if available.
6. Begin with one low-risk, non-client-data repository. Keep production credentials and deployment rights away from the coding account.

## Minimum readiness gates before broader rollout

- Security review of OS-level isolation, service principal permissions, egress rules, sandbox policy, access to GitHub credentials, key management, and secrets in task logs.
- Reliable one-task-only dispatch, no duplicate re-execution, hard cancellation of all spawned processes, timeout/retry policy, and a restart/recovery test.
- Accurate, comparable cost and usage metrics; explicit daily/weekly work budgets and suspension on allowance exhaustion.
- Independent tests (not just self-reported successes), diff inspection, PR-only permissions, and human approval.
- Avoid any production or client-data project until the above criteria are satisfied.

## Evidence provenance

Observed terminal output supplied during 14 November 2026 pilot: direct Codex JSONL summary; ORCH `task show`/agent usage report; AoE terminal capture and independent unit test results. No additional benchmark was launched to create this report.
