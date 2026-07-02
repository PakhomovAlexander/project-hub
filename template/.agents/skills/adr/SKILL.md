---
name: adr
description: Record an architecture decision as a new ADR — numbered, honest about the rejected options, and wired into the index, the plan, and the invariants. Use when a significant decision was just made or needs recording.
argument-hint: [decision title]
---

# Record an architecture decision

1. **Number it.** List `docs/adr/` and take the next `000N`. The file is
   `docs/adr/000N-short-kebab-title.md`, copied from `docs/adr/_template.md`.
2. **Title = the decision**, as a short active statement ("Use Postgres as the primary
   store"), never a topic ("Database choice").
3. **Fill it honestly.**
   - Context + decision up top: what forced the choice, what was decided.
   - Considered options: the ones actually weighed, each with why it won or lost. The
     rejected options with reasons are the most valuable part — don't skip them.
   - Consequences: what becomes true now, including the downsides being accepted.
   - Status: `accepted (YYYY-MM-DD)` if the human confirmed it, else `proposed`.
4. **Wire it in** (same change):
   - Add it to the index list in `docs/adr/README.md` and to the Decisions section of
     `docs/index.md`, each with a one-line summary.
   - If the project plan has a decision register (`docs/plan.md`), add or update its row.
   - If the decision creates or changes a hard rule, update the **Invariants** section of
     `AGENTS.md`, citing `ADR-000N`.
5. **Superseding?** If this replaces an earlier ADR: mark the old one
   `superseded by ADR-000N` with a link, and link back from the new one. That status flip
   is the *only* edit ever made to an accepted ADR — never rewrite one.
