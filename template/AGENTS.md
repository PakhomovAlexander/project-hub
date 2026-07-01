# AGENTS.md — {{PROJECT_NAME}} Project Hub

<!-- TEMPLATE: the vendor-neutral entry point for ANY coding agent working in this hub. Keep
     it a short router to the canonical docs — the full working agreement lives in CLAUDE.md;
     don't copy the rules here (a second copy just drifts). Remove this comment. -->

This hub is the **cockpit** for {{PROJECT_NAME}}: it holds the docs and controls, not the
product code (that lives in the linked repos under `repos/`). Whatever agent you are, start here.

## Read first, in order

1. [`CONTEXT.md`](CONTEXT.md) — the shared language / glossary. Use these words.
2. [`CLAUDE.md`](CLAUDE.md) — the **working agreement**: the invariants you must never break,
   plus PR/CI, verification, issue-lifecycle, and doc-honesty rules. It is the source of truth
   for how to work here — follow it exactly. (Claude Code loads it natively; every other agent
   should read it via this pointer.)
3. [`docs/index.md`](docs/index.md) — the map of everything: plan, tracker, ADRs, per-repo docs.

## Before you change anything

- `make status` — know each linked repo's branch + dirty state first.
- Check [`docs/tracker.md`](docs/tracker.md) for what's in flight.
- Running several agents at once? Give each its own git worktree — see
  [`docs/parallel-agents.md`](docs/parallel-agents.md).
