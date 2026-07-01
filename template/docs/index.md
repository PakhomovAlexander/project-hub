# Docs

Map of everything in the hub.

## Start here

- [`../CONTEXT.md`](../CONTEXT.md) — shared language / glossary. Read first.
- [`plan.md`](plan.md) — the master plan: scope, workstreams, timeline, decisions.
- [`tracker.md`](tracker.md) — **live status board.** Where everything stands right now.
- [`service-catalog.md`](service-catalog.md) — **every service & repo + doc status**, the
  documentation standard, and the rollout plan. Start here to find a service or its doc.
  <!-- TEMPLATE: delete this line for a single-repo hub. -->

## Architecture references (deep dives)

<!-- TEMPLATE: link the Tier-2 cross-cutting subsystem docs (docs/<subsystem>.md) as you
     write them — a flow worth tracing end-to-end. Delete this section if you have none. -->

- {{`<subsystem>.md` — one line on the flow it traces.}}

## Decisions (ADRs)

<!-- TEMPLATE: list each ADR with a one-line summary as you add them. -->

- [`adr/0001-record-architecture-decisions.md`](adr/0001-record-architecture-decisions.md)
  — we record decisions as ADRs.
- [`adr/_template.md`](adr/_template.md) — copy this to write a new ADR.

## In-flight workstream docs

<!-- TEMPLATE: link the deep design docs for work currently in flight. -->

- [`workstreams/_template.md`](workstreams/_template.md) — copy this to start a workstream doc.

## Process

- [`issue-lifecycle.md`](issue-lifecycle.md) — how backlog items move.
- [`parallel-agents.md`](parallel-agents.md) — run several agents over the hub at once,
  each in its own git worktree (`make worktree`).

## Per-repo overviews

<!-- TEMPLATE: one line per linked repo; delete for a single-repo project. -->

- [`repos/_template.md`](repos/_template.md) — copy this for each linked repo.
