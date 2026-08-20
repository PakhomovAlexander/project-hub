---
name: self-review-heavy
description: Heavy self-review for substantial changes, driven by the Review Kernel — reviewctl runs a sandboxed, budgeted reviewer pipeline against committed HEAD; you work the findings ledger, resolve with evidence, and re-run to convergence. Expensive by design; use before opening or updating a PR for engine-grade work.
argument-hint: "[campaign-name] [focus: free text] [overrides: pipeline=FILE repo=DIR]"
compatibility: Requires git and the review kernel workspace (tools/review-kernel in the hub, pinned Rust toolchain), a .review/ pipeline in the target repo, and authenticated claude/codex CLIs for model reviewers.
metadata:
  version: "2.0"
  origin: project-hub
---

# Heavy self-review (kernel-driven)

A pre-PR quality gate for changes that matter. The **Review Kernel** executes the review:
sandboxed reviewers, typed contracts, budgets, an append-only event log, and a findings
ledger with convergence — all deterministic code (`tools/review-kernel/`; the human guide,
worked example, and configuration reference are
[`docs/self-review-heavy.md`](../../../docs/self-review-heavy.md)). You — the agent
reading this — drive the **loop around it**: run a round, triage the ledger, fix, record
resolutions, run the next round. Reviewers never edit anything; **you are the only fixer.**

**Cost warning:** the reviewers are frontier models at high reasoning (~70k tokens per
round observed on the hub pipeline). Use this for substantial changes, not one-liners —
for those, say so and suggest a plain review.

## 0 · Preconditions

- **The kernel binary.** Build once per session:
  `cargo build --release -p reviewctl --manifest-path <hub>/tools/review-kernel/Cargo.toml`
  → `<hub>/tools/review-kernel/target/release/reviewctl` (`reviewctl` below).
- **A committed HEAD.** A run reviews committed content only; uncommitted work is
  invisible. If the target repo is dirty, stop and ask — never review a state the author
  did not intend, and never commit their work for them just to review it.
- **A `.review/` in the target repo** (pipeline TOML, reviewer packages, lockfile — the
  hub's own is the model). If the repo has none, offer to onboard it first; do not
  improvise a pipeline inline.
- Run from the target repo's root, so `.review/` paths and the state directory resolve.

## 1 · Name the campaign

One campaign = one logical review, across as many rounds as it takes. Slug it from the
branch or task (`float-int-unification`, `pr-221-flakes`). The campaign's whole history —
event log, artifacts, ledger — lives in `.review/runs/<campaign>/` (gitignored state, not
repo content). Re-invoking with the same name **continues** the campaign; never start a
fresh campaign to escape an inconvenient ledger.

## 2 · Run a round

```
reviewctl run --campaign <name> --authority <trusted-rev> [--restart-round] [--focus "<campaign focus>"]
```

`--authority` is required only when the Campaign opens. Continuations reuse the stored Campaign
Manifest and do not resolve that ref again. The kernel then captures HEAD, runs the gate checks in a read-only sandbox, dispatches the
reviewers concurrently under the pipeline's budgets, reduces their reports into the
ledger, and prints every node outcome, the findings, the spend, and the verdict. From
round 2 on, every reviewer receives the campaign's prior findings as labelled data and is
asked to confirm, dispute, or drop each one.

Exit codes: `0` converged · `3` not converged / exhausted · `4` incomplete (a node failed
or was suppressed — read the node outcomes; an incomplete run can never pass).

## 3 · Work the ledger

```
reviewctl ledger --campaign <name>        # key  severity  status  file:line  title
```

Triage every open finding — never silently skip one:

- **Real defect** → fix it properly. Batch fixes into deliberate, locally-verified
  commits (the CI-discipline rules apply to review rounds too).
- **Wrong finding** → gather the evidence, then
  `reviewctl resolve --campaign <name> <key> rejected --note "<why, with evidence>"`.
- **Real but deliberately not fixing** → `wontfix` **requires the owner's explicit
  sign-off**; record who agreed in the note.
- **A fix that rests on a performance claim is not `fixed` until the measurement exists.**
  The kernel does not track this for you — the reviewer contract carries a
  `benchmark_demands` field, but nothing stores or replays it — so the bar is yours to
  hold: put the number in the resolution note
  ([`references/benchmark-validity.md`](references/benchmark-validity.md)).

After fixing and committing:

```
reviewctl resolve --campaign <name> <key> fixed --note "<what changed, which commit>"
```

Every resolution carries a note naming the change. A resolution without a real fix is
pointless: the next round's reviewers re-find the defect and the ledger reopens it.

## 4 · Iterate to convergence

Commit the round's fixes, then run the same campaign again. Repeat until:

After an incomplete run, a plain rerun resumes the same pinned Subject and only retries
missing work. If fixes were committed after that incomplete run, pass \u0060--restart-round\u0060 to
supersede its epoch, capture the new \u0060HEAD\u0060, and rerun every node.

- **`verdict Pass`** — the only statement that may be reported as converged. Never claim
  convergence from your own reading of the ledger, and never weaken the pipeline, its
  budgets, or the convergence policy mid-campaign to reach green.
- **`Exhausted`** — the round cap hit with work outstanding. Stop and report honestly;
  the owner decides whether to raise `max_rounds` or ship with the ledger open.

## 5 · Report

Use `reviewctl ledger --campaign <name> --long` for finding bodies and fixes, and
`reviewctl show --campaign <name> <key>` for one finding's complete reports and history.
Generate the closing record with `reviewctl report --campaign <name> --format md`, then
summarize it. The ledger is the record; your summary is not a substitute.

## Legacy

Version 1 of this skill was a shell harness (`scripts/`, stage playbooks, the `srh-*`
stage-runner agents). The kernel replaced its orchestration end to end, and only what
something still uses was kept:

- `ledger.sh` and `checks.sh` are the reference implementation the kernel is proved
  against — `tools/review-kernel/fixtures/synthetic/generate.sh --check` regenerates the
  fixture corpus by running them, gated in CI.
- `bundle.sh` captures a review bundle, which is how a hub freezes its own private
  acceptance corpus (`tools/review-kernel/fixtures/legacy/README.md`).
- `findings.schema.json` is the shape both the above and the kernel's reviewer contract
  speak.

The stage playbooks, the stage-runner agents, and the Codex stage script are retired: the
kernel drives Codex through `review-runner-codex` instead.
