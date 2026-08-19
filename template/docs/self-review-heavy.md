# `/self-review-heavy` — how it works, and how to configure it

The heavy pre-PR review, explained for humans. The agent-facing procedure lives in
[`.agents/skills/self-review-heavy/SKILL.md`](../.agents/skills/self-review-heavy/SKILL.md);
this page is the mechanism underneath it and the configuration reference — read it when you
adopt the skill, tune its pipeline, or want to understand a verdict it produced.

## The division of labor

`/self-review-heavy` is a **loop an agent drives around a deterministic Rust binary**. The
binary — `reviewctl`, built from [`tools/review-kernel/`](../tools/review-kernel/) — runs one
*round*: capture HEAD, gate-check it, dispatch model reviewers in sandboxes, fold their
reports into a findings ledger, print a verdict. The agent (or you, by hand) triages the
ledger, fixes, records resolutions, and runs the next round of the same *campaign* until it
converges.

The boundary is deliberate and structural: **reviewers never edit anything.** They run
against sandboxed copies, return typed findings, and only the kernel integrates results.
Publishing to a branch or PR stays an explicit human action.

## Where everything lives

```
<hub or target repo>/
  .review/
    pipelines/heavy.toml      the pipeline: checks, node graph, budgets, convergence
    reviewers/
      architecture/
        reviewer.toml         runner: program (claude|codex) + model/effort flags
        reviewer.md           the prompt (part of the pinned package)
      performance/            same shape
    review.lock               sha256 digest pinning each reviewer package
    runs/<campaign>/          gitignored state, one directory per campaign
      cas/                    content-addressed artifacts (reports, snapshot manifests)
      events.sqlite           append-only event log — the ONLY source of truth

  tools/review-kernel/        the kernel workspace; builds the reviewctl binary
```

The ledger you triage is **not stored anywhere**. It is a projection rebuilt by replaying
`events.sqlite` from the top on every command (`Ledger::rebuild` in
`tools/review-kernel/crates/review-store/src/ledger.rs` — the only constructor, so
hand-edited state has no way in). Delete the projection, replay, same answer.

## The central idea

The relation defect ↔ ledger-finding is **many-to-many across reviewers and rounds**. Two
reviewers reporting the same defect, or round 3 re-reporting round 1's defect, must land on
*one* finding — and which report "owns" it must not depend on which model happened to finish
first. Two mechanisms carry this:

1. **The fingerprint key** (`legacy_fingerprint` in
   `crates/review-store/src/legacy.rs`): `sha256(file + "|" + normalized_title)`, first
   12 hex characters. The title is ASCII-lowercased and whitespace-squeezed; an empty `file`
   becomes the sentinel `(change-wide)`. Same file + same-ish title = same finding, forever,
   across rounds.
2. **Canonical admission order**: reviewers run concurrently, but their results are folded
   in node-ID order (alphabetical), never completion order. Otherwise scheduling would
   decide finding ownership, and a replay could not reproduce the run it replays
   (proved in `crates/review-runner/tests/determinism.rs`).

## One round, end to end

`reviewctl run --campaign <name>` (see `crates/reviewctl/src/main.rs`):

```
 .review/pipelines/heavy.toml + review.lock  --load, verify digests--+
                                                                     v
 git HEAD --offline capture, safe-subcommand allowlist--> snapshot (content digest)
                                                                     |
     closed rounds counted from the event log --------------> round N
     ledger minus rejected/wontfix rows ---------> prior-findings artifact
                                                                     v
   +------ the pipeline DAG (heavy.toml [[nodes]] / [[edges]]) ----------------+
   |                                                                           |
   |  generation -- findings -------------+---------------+                    |
   |                                      v               v                    |
   |  gate -- decision --+----> architecture        performance                |
   |  (the [[checks]],   |      (claude, sandbox)   (claude, sandbox)          |
   |   in a read-only    |            | result            | result             |
   |   sandbox)          |            v                   v                    |
   |                     |          gather (canonical order)                   |
   |  gate FAILS?        |            | reports                                |
   |  reviewers never    |            v                                        |
   |  dispatched -->     |          ledger fold                                |
   |  exit 4, round      |            |                                        |
   |  NOT consumed       |            v                                        |
   +----------------------          convergence check ------------------------ +
                                      |
             exit 0  verdict Pass  ·  exit 3  not converged / exhausted
             exit 4  Incomplete (a node failed or was suppressed — never a pass)
```

Each reviewer invocation runs the package's CLI (`claude -p --output-format json` with the
package's model flags), `-C`'d into a throwaway sandbox copy of the snapshot. The prompt is
the package's `reviewer.md` plus a result contract, plus the run's `--focus` text, plus the
prior findings rendered as labelled data. From round 2 on, each reviewer must confirm,
dispute, or drop each carried prior finding — a dispute lands the finding as `contested`.

## A worked campaign, three rounds

Reviewers: `architecture` (arch) and `performance` (perf). Defaults from
[`heavy.toml`](../.review/pipelines/heavy.toml): convergence gate `major`,
`clean_rounds = 1`, `max_rounds = 3`. Keys below are illustrative.

**Round 1.** The gate passes. Reports, admitted arch-first (canonical order):

```
                                                            fingerprint
 arch: Makefile,        "teardown leaves a stale lock",  major   --> k=a1b2c3d4e5f6  NEW
 arch: docs/runbook.md, "teardown steps out of date",    minor   --> k=b7c8d9e0f1a2  NEW
 perf: Makefile,        "Teardown  leaves a stale LOCK", blocker --> k=a1b2c3d4e5f6  same key
       (lowercase + whitespace-squeeze make the titles equal — that IS the collapse)
```

The fold for perf's report (`apply_report` in `crates/review-store/src/ledger.rs`): the
finding exists, its status is active, and blocker outranks major → **escalated**. Escalation
calls `adopt`, so the re-reporter's severity, body, line and **source** all replace what was
there: severity becomes blocker, `news_round = 1`, the finding's source becomes `perf`, and
both reports stay attached.

Canonical admission order decides ownership for exactly one case: a plain **duplicate**, where
the later report changes nothing and the first reporter keeps the finding. Everything that
calls `adopt` reassigns `source` to the re-reporter — escalation does, and so does a **reopen**
of a fixed finding, which adopts regardless of severity and can therefore lower it. The rule is
not "highest severity wins" but "the report the ledger acted on owns the finding".

```
 ledger after round 1:
 key            sev      status  news  reports        source
 a1b2c3d4e5f6   blocker  open    1     [arch, perf]   perf   <- adopted on escalation
 b7c8d9e0f1a2   minor    open    1     [arch]         arch
```

Convergence (`convergence` in the same file): `open_blocking` counts active findings at or
above the gate — **1** (the minor one never counts). `new_recent` counts findings whose
`news_round` is inside the clean window — **1**. Not converged; `reviewctl` exits 3.

The operator fixes the Makefile, commits, then records both dispositions:

```sh
reviewctl resolve --campaign teardown-fix a1b2c3d4e5f6 fixed    --note "quote the var; commit 1234abc"
reviewctl resolve --campaign teardown-fix b7c8d9e0f1a2 rejected --note "doc matches HEAD as of 1234abc"
```

**Round 2.** One closed round exists, so this run is round 2. The prior-findings artifact
carries only the fixed finding — rejected and wontfix findings are never handed back
(re-litigation cannot change their status, so it would only burn review budget). Suppose:

```
 perf: Makefile, "teardown leaves a stale lock", major --> k=a1b2c3d4e5f6
       status was fixed in an EARLIER round --> REOPENED: open again, news_round=2,
       severity adopted from the re-report (even if lower than before)
 arch: docs/runbook.md, "teardown steps out of date", major --> k=b7c8d9e0f1a2
       declined + higher severity --> severity adopted, news_round=2, status STAYS rejected
 arch: "",  "no test covers the teardown path", major --> file empty -> "(change-wide)"
       k=c3d4e5f60718  NEW
```

Convergence: two findings block (`a1…` reopened, `c3…` new), and three count as news —
including the *rejected* `b7…` (see below). Round 2 of 3: not converged, exit 3. The
operator fixes the reopened finding properly, adds the missing test, resolves both `fixed`.
The rejected finding needs nothing — its status never moved.

**Round 3.** Prior findings carried: the two fixed ones. The reviewers confirm both and
report nothing new. Nothing is open at or above the gate, nothing has news inside the clean
window, and the round count satisfies `clean_rounds` → **Converged, verdict Pass, exit 0.**
Resolutions never touch `news_round` — only reports do — which is exactly why the round-2
fixes had to *survive* round 3's review before the run could pass.

Had a gate check failed in any round, both reviewers would have been *suppressed* — never
dispatched — and the run would exit 4 (Incomplete). Incomplete runs do not close a round:
an infrastructure failure re-enters the same round instead of consuming one of the three.

## Deliberate behaviors that look like bugs

- **A finding you fixed this round still blocks convergence.** The news counter ignores
  status by design: a fix must survive one more review round. `clean_rounds = 1` therefore
  means "minimum two rounds if round 1 found anything at or above the gate".
- **A rejected finding can delay convergence.** A reviewer independently re-finding your
  rejection at *higher* severity bumps its news round (status still stays rejected). That
  costs a round — deliberately: it forces the escalation in front of you instead of letting
  the rejection swallow it. Status never auto-reopens for declined findings, because
  reviewers only ever see open claims and would rediscover declined ones forever.
- **Reopening can downgrade severity.** A re-report after a fix adopts the re-reporter's
  severity unconditionally, even when it is lower than what the finding had before.
- **A check that could not run is not a pass.** `not_run` blocks a required gate exactly
  as a failure does — and so does a gate with no required checks at all: a vacuous green is
  the most dangerous kind.

## Invariants

What a future editor would be breaking:

- Results are admitted in node-ID order, never completion order — reorder that and both the
  event stream and duplicate ownership become nondeterministic, and replay lies. (Ownership of
  an *escalated* finding is decided by severity, not order: escalation adopts the re-reporter.)
- The ledger is only ever rebuilt from the event log; nothing writes projection state
  directly.
- `rejected` / `wontfix` never travel to reviewers and never auto-reopen.
- A suppressed node, a `not_run` check, and a vacuous gate are never a pass; only
  `verdict Pass` may be reported as converged.
- The fingerprint normalization is bug-compatible with the legacy shell harness on purpose
  (ASCII-only lowercasing) — "fixing" it orphans every existing campaign key.

## Configuration reference

Everything lives in the target repo's `.review/`, plus a few CLI flags. This hub's own
`.review/` is the model; onboarding another repo means copying that shape into it and
running from its root.

### `pipelines/heavy.toml`

| Section | What you set |
|---|---|
| `[[checks]]` | Gate programs. The program and every option are trusted literals from this file; a value derived from the change under review must be marked `untrusted` — it then can never occupy an option position (a leading `-` is refused, and the check records `not_run`, never "passed"). |
| `[[nodes]]` / `[[edges]]` | The pipeline DAG. Adding a reviewer = one `[[nodes]]` entry (kind `reviewer`, `package = "<name>"`, `gated_by = "gate"`) plus edges wiring `gate.decision`, `generation.findings`, and its `result` into `gather`. Unknown fields, unwired inputs, and dangling edges are load-time fatal errors — a pipeline that is 90% valid is not 90% of a review. |
| `[budgets]` | `unit = "tokens"` with `attempt` and `run` caps. Budgets reserve **before** dispatch — a dispatch that cannot reserve does not happen; exhaustion finishes in-flight attempts and reports Incomplete. |
| `[convergence]` | `clean_rounds` (quiet rounds required), `max_rounds` (then Exhausted — raising it is the owner's call), `gate` (`minor` / `major` / `blocker` — the minimum severity that blocks). |

### Reviewer packages — `reviewers/<name>/`

`reviewer.toml` names the runner (`program = "claude"` or `"codex"` — the two adapters
`reviewctl` knows) and its model flags (e.g. `--model opus --effort xhigh`). `reviewer.md`
is the prompt. Both sit under the lockfile's content digest, so **any edit requires
re-locking**:

```sh
cd tools/review-kernel
cargo run -p review-config --example lock -- ../../.review/reviewers architecture performance \
  > ../../.review/review.lock
```

(list every package name). A digest mismatch at load is fatal — an unpinned or tampered
prompt cannot silently run. A checked-in test
(`crates/review-config/tests/definition.rs`) loads this repo's own pipeline through its
lockfile on every test run, so forgetting to re-lock fails CI, not a live review.

### `reviewctl` flags

| Flag | Meaning |
|---|---|
| `--campaign NAME` | Join a persistent ledger; the same name continues the campaign. Without it, a run is identified by its snapshot and shares the `local` state directory. |
| `--focus "text"` | Appended to every reviewer prompt, this round only — a narrowing, never a replacement. |
| `--repo DIR` | Repo to review (default `.`). |
| `--pipeline FILE` | Default `.review/pipelines/heavy.toml`. |
| `--state DIR` | Override the state directory (default `.review/runs/<campaign>`). |
| `--timeout-secs N` | Per-reviewer-invocation timeout (default 1800). |

`reviewctl ledger --campaign NAME` prints the findings machine-readably;
`reviewctl resolve --campaign NAME KEY STATUS [--note TEXT]` records a disposition
(`open`, `fixed`, `rejected`, `wontfix`, `contested`).

### Cost

Reviewers are frontier models at high reasoning effort. Budget for tens of thousands of
tokens per round on a modest pipeline; scale the `[budgets]` caps and the reviewer set to
what your project can spend. Use the skill for substantial changes, not one-liners.

## The legacy shell harness

Version 1 of this skill was a shell pipeline
(`.agents/skills/self-review-heavy/scripts/`). The kernel replaced its orchestration end to
end, but the scripts remain **deliberately**: they are the executable specification that
regenerates the kernel's synthetic fixture corpus
(`tools/review-kernel/fixtures/synthetic/generate.sh --check`, gated in CI). Real frozen
review bundles are private per-hub data — see
[`tools/review-kernel/fixtures/legacy/README.md`](../tools/review-kernel/fixtures/legacy/README.md)
for how a hub captures its own acceptance corpus.
