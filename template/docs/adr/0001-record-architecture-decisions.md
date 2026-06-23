# Record architecture decisions

**Status:** accepted

We need to record the architectural decisions made on this project — the significant ones
that shape structure, dependencies, interfaces, or process — so that the reasoning behind
them survives turnover, time, and the arrival of agents who weren't in the room.

## Considered options

- **Keep decisions in people's heads / chat history.** Zero overhead, but the rationale
  evaporates: six months on, no one remembers which alternatives were weighed or why one
  won, and the decision gets relitigated. Rejected.
- **One big design doc, edited in place.** Better than nothing, but rewriting it loses the
  history of *how* the design changed, and merges become contested. Rejected as the system
  of record.
- **Lightweight ADRs** (this decision). One file per decision, immutable once accepted,
  superseded by new ADRs rather than edited. Chosen — it's cheap, it preserves the
  supersession chain, and it puts the *why* next to the code and plan.

## Consequences

- Significant decisions get a numbered file in `docs/adr/` with context, options, and
  consequences.
- Accepted ADRs aren't rewritten; a changed decision becomes a new ADR that supersedes the
  old one (with links both ways).
- Invariants in `CLAUDE.md` and entries in the plan's decision register cite their ADR, so a
  rule always traces back to its rationale.

<!-- TEMPLATE: this ADR is generic and worth keeping as-is. Write your project's real
     decisions as 0002, 0003, … using _template.md. -->
