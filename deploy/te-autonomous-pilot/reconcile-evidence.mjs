#!/usr/bin/env node
/**
 * Development Chief of Staff: deterministic project-evidence ledger compiler.
 * This reads *private* JSONL snapshots, and emits versioned living briefs.
 * It does not scrape ChatGPT, make LLM calls, or change project trackers.
 *
 * node reconcile-evidence.mjs /private/evidence.jsonl /private/briefs.json
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const KINDS = new Set(["proposal", "decision", "scope_change", "status", "implementation", "verification", "failure", "blocker", "correction", "priority_change"]);
const SOURCES = new Set(["chatgpt_decision", "github_issue", "github_pr", "github_commit", "github_actions", "portfolio", "manual", "app_probe"]);
const AUTHORITY = new Set(["user_explicit", "business_owner", "github_evidence", "portfolio_record", "agent_inference"]);
const STATES = new Set(["proposed", "approved", "implemented", "merged", "deployed", "verified", "failed", "blocked", "recorded"]);

function validIso(value) {
  return typeof value === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d/.test(value) && Number.isFinite(Date.parse(value));
}
function checkedEvent(e, n) {
  if (!e || typeof e !== "object" || Array.isArray(e)) throw Error("Event " + n + " must be object");
  for (const k of ["event_id", "project_key", "aspect", "summary", "occurred_at", "observed_at", "kind", "source", "authority", "state"]) {
    if (typeof e[k] !== "string" || !e[k].trim()) throw Error("Event " + n + " missing " + k);
  }
  if (!/^[a-z0-9][a-z0-9_-]{1,79}$/.test(e.project_key)) throw Error("Invalid project key on event " + n);
  if (!/^[a-z0-9][a-z0-9_-]{1,79}$/.test(e.aspect)) throw Error("Invalid aspect on event " + n);
  if (e.event_id.length > 240 || e.summary.length > 5000) throw Error("Event fields too large " + n);
  if (!validIso(e.occurred_at) || !validIso(e.observed_at)) throw Error("Invalid ISO timestamps on event " + n);
  if (!KINDS.has(e.kind) || !SOURCES.has(e.source) || !AUTHORITY.has(e.authority) || !STATES.has(e.state)) throw Error("Unknown event category on line " + n);
  if (e.supersedes_event_ids !== undefined && (!Array.isArray(e.supersedes_event_ids) || !e.supersedes_event_ids.every(x => typeof x === "string"))) throw Error("Invalid supersedes on line " + n);
  return { ...e, supersedes_event_ids: e.supersedes_event_ids || [] };
}

export function reconcile(events) {
  const byId = new Map();
  for (const [i, e] of events.entries()) {
    const clean = checkedEvent(e, i + 1);
    const prior = byId.get(clean.event_id);
    if (prior && JSON.stringify(prior) !== JSON.stringify(clean)) {
      throw Error("Conflicting duplicate event revision: " + clean.event_id);
    }
    byId.set(clean.event_id, clean);
  }
  const all = [...byId.values()].sort((a, b) =>
    a.occurred_at.localeCompare(b.occurred_at) || a.observed_at.localeCompare(b.observed_at) || a.event_id.localeCompare(b.event_id)
  );
  const groups = new Map();
  for (const ev of all) {
    const group = groups.get(ev.project_key) || [];
    group.push(ev);
    groups.set(ev.project_key, group);
  }
  const briefs = [];
  for (const [key, rows] of [...groups].sort(([a], [b]) => a.localeCompare(b))) {
    const decisions = rows.filter(e =>
      ["decision", "scope_change", "correction", "priority_change"].includes(e.kind) &&
      e.state === "approved" && ["user_explicit", "business_owner"].includes(e.authority));
    const superseded = new Set(rows.flatMap(e => e.supersedes_event_ids));
    // Approved decisions can cover different aspects; never let a merged PR
    // silently redefine them. An unresolved same-aspect decision conflict
    // is an explicit item, not a newest-wins overwrite.
    const active = decisions.filter(e => !superseded.has(e.event_id));
    const byAspect = new Map();
    for (const e of active) {
      const list = byAspect.get(e.aspect) || [];
      list.push(e);
      byAspect.set(e.aspect, list);
    }
    const accepted = {};
    const conflicts = [];
    for (const [aspect, candidates] of [...byAspect].sort(([a],[b]) => a.localeCompare(b))) {
      const last = candidates.at(-1);
      accepted[aspect] = candidates.length === 1 ? {
        value: last.summary, event_id: last.event_id, occurred_at: last.occurred_at, state: last.state
      } : null;
      if (candidates.length > 1) {
        // Distinct statements of the same aspect without explicit supersession
        // must not be silently reduced to the most recent one.
        const variants = new Set(candidates.map(e => e.summary.trim()));
        if (variants.size === 1) {
          accepted[aspect] = {
            value: last.summary, event_id: last.event_id, occurred_at: last.occurred_at, state: last.state
          };
        } else {
          conflicts.push({
            aspect, event_ids: candidates.map(e => e.event_id),
            reason: "Conflicting approved claims; scope or supersession unresolved",
            materiality: "unknown"
          });
        }
      }
    }
    const milestones = rows.filter(e => ["implementation", "verification", "failure"].includes(e.kind))
      .map(e => ({
        description: e.summary, state: e.state, source: e.source,
        evidence: e.source_ref || e.event_id, occurred_at: e.occurred_at
      }));
    const tracker = rows.filter(e => e.source === "portfolio").at(-1);
    const backlog = rows.filter(e => e.source === "github_issue" &&
      !superseded.has(e.event_id)).slice(-15).map(e => ({
      summary: e.summary, evidence: e.source_ref || e.event_id, state: e.state
    }));
    const ledger = {
      project_key: key,
      current_objectives: accepted,
      conflicting_decisions: conflicts,
      recent_delivery_evidence: milestones.slice(-20),
      current_github_backlog: backlog,
      portfolio_context: tracker ? {
        summary: tracker.summary, date: tracker.occurred_at, source_ref: tracker.source_ref || tracker.event_id,
        advisory_only: true
      } : null,
      counts: {
        evidence: rows.length, approved_decisions: decisions.length,
        delivered_or_verified: milestones.filter(e => ["deployed", "verified"].includes(e.state)).length
      },
      last_evidence_at: rows.reduce((max, e) => e.observed_at > max ? e.observed_at : max, ""),
      attention: conflicts.length ? "reconcile_if_blocking" : "none",
      agent_action: conflicts.length ? "continue_unaffected_work" : "evaluate_next_safe_task",
      _source_event_ids: rows.map(e => e.event_id)
    };
    ledger.revision = crypto.createHash("sha256").update(JSON.stringify(ledger)).digest("hex").slice(0, 16);
    briefs.push(ledger);
  }
  return { schema_version: 1, projects: briefs };
}

function main() {
  if (process.argv.length !== 4) {
    console.error("Usage: node reconcile-evidence.mjs /private/evidence.jsonl /private/briefs.json");
    process.exit(2);
  }
  const [input, output] = process.argv.slice(2);
  const st = fs.statSync(input);
  if (!st.isFile() || (st.mode & 0o077) !== 0) throw Error("Evidence file must have mode 0600");
  const events = fs.readFileSync(input, "utf8").split(/\r?\n/).filter(x => x.trim())
    .map((line, i) => {
      try { return JSON.parse(line); }
      catch { throw Error("Malformed JSON evidence line " + (i + 1)); }
    });
  const result = reconcile(events);
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  const tmp = output + "." + process.pid + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(result, null, 2) + "\n", { mode: 0o600, flag: "wx" });
  fs.chmodSync(tmp, 0o600);
  fs.renameSync(tmp, output);
  console.log("PROJECT_BRIEFS=" + result.projects.length);
  console.log("CONFLICTED_PROJECTS=" + result.projects.filter(p => p.conflicting_decisions.length).length);
}

if (process.argv[1] && import.meta.url === new URL("file://" + path.resolve(process.argv[1])).href) main();
