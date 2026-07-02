# Service catalog & documentation plan

<!-- TEMPLATE: an agent-facing knowledge base so a future session can LOOK A THING UP
     instead of re-deriving it. Most useful for a multi-repo/multi-service product; DELETE
     this file for a small single-repo hub (the repo's own README is enough). Keep it lean:
     the catalog is a menu, not a mandate. Replace the example rows; remove TEMPLATE comments. -->

The map of **every service and repo** in the project, plus the plan to document them. This
file is both the **catalog** (what exists, where, doc status) and the **standard** (how we
document + the rollout order). It's a living tracker: when a doc lands, flip its status here
in the same PR.

## How to use this

1. Find the service in the [catalog](#catalog). The row tells you **what it is, its source
   repo, its deploy target, and its doc status**.
2. ✅ → follow the link to the reference doc. ◐ → an overview exists but it's thin. ☐ → not
   documented yet (a candidate to write before/while you work on it).
3. **Writing or deepening a doc?** Follow the [standard](#documentation-standard), then flip
   this catalog's status in the same PR.

**Status legend:** ✅ documented · ◐ overview only · ☐ to do · ⊘ parked (catalog-only, no
doc planned — experiments/legacy).
**Priority:** **P1** critical path · **P2** core product · **P3** integrations & ops · **P4** depth & parked.

## Documentation standard

### Where docs live (all in this hub — agent-accessible by design)

| Tier | What | Home | Example |
|---|---|---|---|
| **0 — Catalog** | one line per service + status | this file | — |
| **1 — Reference** | 1–2 pages per repo/service | `docs/repos/<name>.md` | [`repos/_template.md`](repos/_template.md) |
| **2 — Deep dive** | a cross-cutting subsystem / flow | `docs/<subsystem>.md` | — |

Most services need only a **Tier-1** reference (copy [`repos/_template.md`](repos/_template.md)).
Reserve **Tier-2** for subsystems with a real cross-service flow worth tracing end-to-end.

### Conventions (what makes these docs worth trusting)

- **Honesty:** mark **confirmed** (read from source) vs **inferred**; date the read; end with
  "verify before relying on specifics." If the source isn't in the workspace, say so.
- **Cite paths into linked repos as inline code** (`repos/<repo>/...`), never as markdown
  links — `repos/` is gitignored, so links into it break docs CI and fresh clones. Links
  between the hub's own tracked docs stay real links, kept green by docs CI (markdownlint +
  an offline link check) and `scripts/verify.sh`.
- **Note the invariants** that apply to each service (link the ADR), and its **deploy status /
  gap** — the thing an agent most needs before touching it.
- **Don't duplicate the repo:** link to code, don't transcribe it. Capture what's *not*
  obvious from the code — flows, contracts, config/secret locations, gotchas.

## Rollout plan

<!-- TEMPLATE: sequence by criticality × friction — document the things you keep re-deriving
     and that gate delivery, first. Delete if you don't need a staged plan. -->

- **Phase 1 — critical path (P1).** The services that must work for the product to work.
- **Phase 2 — core product (P2).** The main feature surface.
- **Phase 3 — integrations & ops (P3).** Bots, integrations, release/build/ops tooling.
- **Phase 4 — depth & parked (P4).** Module-level infra depth; catalog-only for experiments.

## Catalog

<!-- TEMPLATE: one row per service. Group by domain when the list gets long. -->

### A. {{Domain / area}}

| Service | What it is | Source | Deploy | Status |
|---|---|---|---|---|
| {{service-a}} | {{one line}} | `{{repo-a}}` | {{chart / target}} | ☐ P1 |
| {{service-b}} | {{one line}} | `{{repo-b}}` | {{chart / target}} | ☐ P2 |

---

_Totals: {{N}} services · {{M}} repos. **Documented:** {{…}}. **Remaining:** {{…}}._
