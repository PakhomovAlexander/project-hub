# {{PROJECT_NAME}} tracker

Live status board. The plan is in [`plan.md`](plan.md); this is **where it stands**.
Maintain it as work moves — it's only useful if it's current.

**Legend:** ☐ not started · ◐ in progress · ☑ done · ⚠ decision needed / blocked
**Snapshot:** {{TODAY}} — {{one-line "what's true right now".}}

<!-- TEMPLATE: when reality diverges from the plan, say so plainly here — a blockquote that
     names what changed. An honest tracker is the whole point. -->

> {{Reality vs the plan: anything the plan got wrong or that has since moved.}}

---

## In flight now

| Item | State | Where | Next action |
|------|-------|-------|-------------|
| {{item}} | ◐ | [{{workstream/PR}}]({{link}}) | {{the next concrete step}} |

## Open decisions / gaps

<!-- TEMPLATE: things awaiting a human call. Mark resolved ones ☑ and strike them, so the
     history of what was decided stays readable. -->

- ⚠ {{open question that needs a decision}}
- ☐ {{known gap, not yet started}}

## Workstreams

| WS | Workstream | State | Note |
|----|------------|-------|------|
| 1 | {{name}} | ☐ | {{…}} |
| 2 | {{name}} | ☐ | {{…}} |

## External clocks (start early — they gate delivery)

<!-- TEMPLATE: lead-time items you don't control (reviews, approvals, provisioning). Delete
     if none. -->

- ☐ {{external dependency with a long lead time}}

---

## Repo branch snapshot ({{TODAY}})

<!-- TEMPLATE: delete for a single-repo project. Run `make status` for the current view. -->

| Repo | Branch | Dirty |
|------|--------|-------|
| {{repo-a}} | `{{branch}}` | {{no}} |
