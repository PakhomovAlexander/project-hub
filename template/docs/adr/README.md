# Architecture Decision Records

An **ADR** captures one significant decision: the context, the options considered, what was
chosen, and the consequences. We keep them because the *why* behind a decision is the first
thing lost to time — and the most expensive to reconstruct.

## How we use them

- One decision per file, numbered: `000N-short-kebab-title.md`. Start a new one by copying
  [`_template.md`](_template.md).
- ADRs are **immutable once accepted**. Don't rewrite history — when a decision changes,
  write a **new** ADR and mark the old one *superseded by ADR-000M* (and link forward). The
  supersession chain *is* the record of how thinking evolved.
- Keep them short and honest. Record the options you rejected and *why* — that's the part
  future-you needs.
- Link ADRs from [`../index.md`](../index.md) and reference them by number from
  [`../../AGENTS.md`](../../AGENTS.md) invariants and [`../plan.md`](../plan.md).

## Index

<!-- TEMPLATE: keep this list current as ADRs are added. -->

- [0001 — Record architecture decisions](0001-record-architecture-decisions.md)
