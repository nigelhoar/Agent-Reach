import test from "node:test";
import assert from "node:assert/strict";
import { reconcile } from "./reconcile-evidence.mjs";

function event(id, { project_key = "sample-project", aspect = "objective", summary = "Original scope",
  source = "portfolio", authority = "portfolio_record", kind = "status", state = "recorded",
  occurred_at = "2026-10-01T10:00:00Z", observed_at = "2026-11-14T10:00:00Z",
  supersedes_event_ids = [], source_ref = id } = {}) {
  return { event_id: id, project_key, aspect, summary, source, authority, kind, state, occurred_at, observed_at, supersedes_event_ids, source_ref };
}

test("explicit scope correction wins as approved objective while retaining stale tracker as context", () => {
  const old = event("chat-old", { source: "chatgpt_decision", authority: "user_explicit", kind: "decision", state: "approved", summary: "Build a guided interview", occurred_at:"2026-11-01T10:00:00Z" });
  const revised = event("chat-new", { source: "chatgpt_decision", authority: "user_explicit", kind: "correction", state: "approved", summary: "Passive meeting recorder; no prompts", occurred_at:"2026-11-09T10:00:00Z", supersedes_event_ids:["chat-old"] });
  const merged = event("github-merged", { source: "github_pr", authority: "github_evidence", kind: "implementation", state: "merged", summary: "Implemented login fix", occurred_at:"2026-11-10T10:00:00Z" });
  const plan = reconcile([event("tracker"), merged, revised, old]).projects[0];
  assert.equal(plan.current_objectives.objective.value, "Passive meeting recorder; no prompts");
  assert.equal(plan.portfolio_context.advisory_only, true);
  assert.equal(plan.recent_delivery_evidence[0].state, "merged");
  assert.equal(plan.conflicting_decisions.length, 0);
});

test("unresolved different owner decisions remain conflict, not newest-wins", () => {
  const a = event("a", { source:"chatgpt_decision", authority:"user_explicit", kind:"decision", state:"approved", summary:"Use old system" });
  const b = event("b", { source:"chatgpt_decision", authority:"user_explicit", kind:"decision", state:"approved", summary:"Use new system", occurred_at:"2026-11-13T10:00:00Z" });
  const result = reconcile([a,b]).projects[0];
  assert.equal(result.current_objectives.objective, null);
  assert.equal(result.attention, "reconcile_if_blocking");
  assert.equal(result.agent_action, "continue_unaffected_work");
});

test("github issue or stale portfolio note never becomes an approved user objective", () => {
  const result = reconcile([
    event("issue", { source:"github_issue", authority:"github_evidence", kind:"proposal", state:"proposed" }),
    event("tracker")
  ]).projects[0];
  assert.deepEqual(result.current_objectives, {});
  assert.equal(result.current_github_backlog.length, 1);
});

test("replaying same event does not duplicate evidence; changing revision with same id fails", () => {
  const e=event("x");
  assert.equal(reconcile([e,e]).projects[0].counts.evidence, 1);
  assert.throws(() => reconcile([e,{...e,summary:"changed"}]), /Conflicting duplicate/);
});
