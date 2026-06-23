# {{PROJECT_NAME}} — Plan

<!-- TEMPLATE: the master plan. Scale it to the project — a small effort needs only a few
     of these sections. Keep it as the design record; live status belongs in tracker.md, not
     here. When reality diverges from the plan, note it at the top and point to the tracker.
     Remove TEMPLATE comments as you fill in. -->

**Status:** {{draft / vN}} · **Glossary:** [`../CONTEXT.md`](../CONTEXT.md) · **Decisions:** [`adr/`](adr/)

## 1. Summary

{{Two or three sentences: what {{PROJECT_NAME}} is, who it's for, and what "done" looks like.}}

## 2. Scope

**In scope:** {{what ships / what this effort covers.}}

**Out of scope (deferred):** {{what's explicitly excluded, so it doesn't creep in.}}

## 3. Workstreams

<!-- TEMPLATE: break the work into parallel streams (epics/tracks). Each gets a short
     description; deep ones get their own doc under workstreams/. -->

- **WS1 — {{name}}.** {{one-line description.}}
- **WS2 — {{name}}.** {{description.}}
- **WS3 — {{name}}.** {{description.}}

## 4. Timeline

<!-- TEMPLATE: phases with exit criteria, or a simple milestone list. Delete if not useful. -->

| Phase | What | Exit criteria |
|-------|------|---------------|
| {{0. Prep}} | {{…}} | {{…}} |
| {{1. Build}} | {{…}} | {{…}} |
| {{2. Launch}} | {{…}} | {{…}} |

## 5. Risks

| Risk | Mitigation |
|------|------------|
| {{risk}} | {{how it's mitigated}} |

## 6. Decision register

<!-- TEMPLATE: one line per resolved decision; promote the load-bearing ones to full ADRs. -->

| # | Decision | Resolution |
|---|----------|------------|
| D1 | {{question}} | {{what was decided}} → {{ADR-000X if any}} |
