# Issue lifecycle

<!-- TEMPLATE: adjust to where the backlog actually lives (GitHub Issues / Jira / a tracker
     file) and to your team's conventions. The key idea worth keeping: merge ≠ done. -->

The {{PROJECT_NAME}} backlog is **{{GitHub Issues / Jira / docs/tracker.md}}**.

## States

```
Open → status:in-progress → status:merged → status:done + Close
```

| Label | Meaning |
|-------|---------|
| _(none)_ | Open — in the backlog, not started |
| `status:in-progress` | Someone is actively working it; a branch/PR exists |
| `status:merged` | PR merged, **but not yet verified — keep the issue open** |
| `status:done` | Verified live by a human; closed alongside this label |

## Rules

- **Do not close an issue when its PR merges.** Merge ≠ done. Set `status:merged`.
- An issue closes **only after a human confirms it works** (deployed + checked, where that
  applies).
- Cross-repo work lives as **one tracking issue** that links the per-repo PRs — so the state
  is readable from one place.

## Labels

<!-- TEMPLATE: suggested label families beyond status. -->

- `ws:1`…`ws:N` — which workstream (see [`plan.md`](plan.md)).
- `repo:<name>` — which linked repo.
- `blocked:external` — waiting on a lead-time item (review, approval, provisioning).
