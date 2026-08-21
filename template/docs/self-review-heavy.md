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

`reviewctl run --campaign <name> --authority <trusted-rev>` on the first Round (see
`crates/reviewctl/src/main.rs`); continuation omits `--authority` and reuses the stored manifest:

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
`clean_rounds = 2`, `max_rounds = 4`. Keys below are illustrative.

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
  status by design: a fix must survive the configured quiet window. `clean_rounds = 2`
  guarantees two rounds for an initially clean campaign and normally requires a third
  confirmation round after round-1 findings are fixed.
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
| `[subject]` | `kind = "whole-tree"` reviews the complete captured head. A `diff` pipeline requires generation to emit exactly one `review.kernel/ChangeSet@1`; every reviewer must declare a same-subject `change_set` input and receive that exact artifact from `generation.change_set`. Declaring this section requires pipeline format `version = 2`; version 1 remains readable as legacy `whole-tree`. |
| `[[checks]]` | Gate programs. The program and every option are trusted literals from this file; a value derived from the change under review must be marked `untrusted` — it then can never occupy an option position (a leading `-` is refused, and the check records `not_run`, never "passed"). |
| `[[nodes]]` / `[[edges]]` | The pipeline DAG. A diff reviewer needs `{ name = "change_set", type = "review.kernel/ChangeSet@1", cardinality = "one", optional = false, snapshot_affinity = "same_subject" }`, plus edges wiring `gate.decision`, `generation.findings`, `generation.change_set`, and its `result` into `gather`. Missing exact Change Set wiring, unknown fields, unwired inputs, and dangling edges are load-time fatal errors. |
| `[budgets]` | `unit = "tokens"` with `attempt` and `run` caps. Budgets reserve **before** dispatch — a dispatch that cannot reserve does not happen; exhaustion finishes in-flight attempts and closes the round as `Fail(Exhausted)` (exit 3). |
| `[convergence]` | `clean_rounds` (quiet rounds required), `max_rounds` (then Exhausted — raising it is the owner's call), `gate` (`minor` / `major` / `blocker` — the minimum severity that blocks). |

### Reviewer packages — `reviewers/<name>/`

`reviewer.toml` declares `subjects = ["diff", "whole-tree"]` (or the supported subset) and
names the runner (`program = "claude"` or `"codex"` — the two adapters
`reviewctl` knows) and its model flags (e.g. `--model opus --effort xhigh`). `reviewer.md`
is the prompt. Both sit under the lockfile's content digest, so **any edit requires
re-locking**:

```sh
make review-kernel-lock
```

The target discovers every package, uses the pinned Rust dependency lock, and replaces the
review lock atomically. For an onboarded repository, run
`make review-kernel-lock RK_REVIEW=<target-repo>/.review` from the hub root. A digest mismatch
at load is fatal — an unpinned or tampered
prompt cannot silently run. A checked-in test
(`crates/review-config/tests/definition.rs`) loads this repo's own pipeline through its
lockfile on every test run, so forgetting to re-lock fails CI, not a live review.

### `reviewctl` flags

`reviewctl tui` opens the interactive configuration-proposal and run surface with `PIPELINE GRAPH`,
`PIPELINE POLICY`, `REVIEWERS`, and `PROVIDERS` tabs. `Tab` and `Shift-Tab` cycle those peer views; Vim movement
never changes tabs. The graph tab renders the validated DAG as a strict-ASCII, left-to-right
diagram. Its viewport follows the selected
node and reports clipped directions without overwriting diagram cells. Data dependencies use solid
ASCII routes and `gated_by` scheduler dependencies use dotted routes; exact, complete port mappings
remain visible below the graph. Layout is cached until the pipeline changes, and explicit node,
link, canvas, and routing-work limits reject pathological diagrams before allocation. The policy
subpane edits budgets and convergence, while graph selection edits reviewer
package bindings and reviewer membership. Adding a reviewer clones the
wiring of the first package-backed reviewer and names that template in the status line; pipelines
whose reviewers use different wiring must be edited in TOML. Infrastructure nodes and arbitrary
port contracts remain TOML-owned rather than being guessed by the interface. The reviewer tab discovers the
packaged reviewers already selected by `--pipeline` and can draft model/effort changes without
mutating the repository. Press `s` to export one explicit pipeline/reviewer patch under run state
in the `config-proposals/` directory. Apply and review that patch, commit it, then start a new Campaign
whose `--authority` names that commit by relaunching the TUI. The in-memory draft remains marked
pending after export because an exported file is not execution authority. A resumed Campaign keeps
its original reviewer authority and ignores a newly supplied `--authority`.

Alternatively, keep the TUI open while applying and committing the patch, press `R` to reload the
now-authoritative worktree configuration, then select a new Campaign name and the committed
authority before pressing `r`. Reload refuses package or lock bytes that are still inconsistent.

The runner backend is package-owned and read-only; infrastructure nodes and arbitrary port
contracts stay TOML-owned. Reviewer membership and package bindings are editable by cloning the
validated wiring of an existing package-backed reviewer. Press `r`
only when no configuration proposal is pending; it launches the ordinary `reviewctl run` path and
therefore uses the Campaign's pinned authority, never in-memory or working-tree reviewer settings.
The alternate screen is suspended while checks and reviewers execute and restored for Pass,
Fail, and Incomplete verdicts.

The TUI uses Vim-style navigation: `h`/`j`/`k`/`l` moves through the graph, while `j`/`k`,
`g`/`G`, and `Ctrl-U`/`Ctrl-D` move through lists and policy. Reviewer configuration keeps `h`/`l`
for a full-width `REVIEWERS` → `WORKTREE CONFIG PROPOSAL` → `PINNED-AUTHORITY RUN` pane sequence;
`l` moves forward and `h` moves back. `Tab`/`Shift-Tab` alone cycles top-level tabs, and `Enter` edits the selected
value. Its colors follow those key groups: yellow connects `Tab`/`Shift-Tab` with the top-level tabs, cyan
connects Vim movement keys with focused panes and selected rows/nodes, and green connects mutating
keys with edit prompts and dirty proposals. Color reinforces the labels; it is never the only
indicator.

The `PROVIDERS` tab is a read-only machine-local inventory. It discovers one ambient candidate for
each supported CLI on `PATH` and runs only `claude auth status --json` or `codex login status` with
bounded output and a five-second timeout. Explicit status probes receive the same kind-specific
auth-directory selector the adapters understand; an unset ambient selector remains unset. The
vendor CLI reads its own auth context, while `reviewctl` never reads or prints credential values.
Providers do not enter configuration proposals, reviewer packages, lockfiles, or Campaign authority.
This iteration does not bind reviewers to providers.

Ambient candidates are explicitly labelled unstable: their login can change without changing the
candidate ID. Only a registry entry supplies the operator-named context required by the Provider
definition. Probe output is normalized through fixed auth-type allowlists; raw stdout and stderr
are never rendered. Probes run in bounded groups of four and isolated process groups. Stdout is
read through a nonblocking pipe under a 64 KiB cap and stderr is discarded, so continuous output
cannot starve the deadline. `R` refreshes in the background without changing tabs or proposal state.

Additional accounts use `${XDG_CONFIG_HOME:-~/.config}/reviewctl/providers.toml` (or the file named
by `REVIEWCTL_PROVIDERS_FILE`). IDs are globally unique while kinds may repeat:

```toml
version = 1

[[providers]]
id = "claude-work"
kind = "claude"
auth_dir = "/Users/me/.claude-work"

[[providers]]
id = "claude-personal"
kind = "claude"
auth_dir = "/Users/me/.claude-personal"
```

Registry auth directories must be absolute and distinct for a given kind. The registry cannot
name commands, arguments, arbitrary environment variables, or secrets; `reviewctl` resolves the
fixed `claude` and `codex` commands from `PATH`. A malformed registry is shown as a warning while
implicit providers remain inspectable.
In `PIPELINE GRAPH`, `a` adds a package-backed reviewer and `d` twice removes one. `s` exports a
configuration patch; `R` reloads applied configuration; `r` runs pinned authority; `Esc` cancels
an edit; and `q` quits. Proposal export refuses
package or lock bytes changed by another process while the interface was open. Proposal state may
be outside the repository or below `.review/runs/`; paths that could alias captured reviewer,
pipeline, or lock content are refused.

| Flag | Meaning |
|---|---|
| `--campaign NAME` | Join a persistent ledger; the same name continues the pinned Campaign. Without it, `local` is the Campaign name. |
| `--state DIR` | Store run state at `DIR`; relative paths resolve from the process working directory. Repository-contained state is allowed only below the selected review tree's `runs/` directory. |
| `--authority REV` | Required when opening a Campaign. Resolves the trusted Snapshot that supplies pipeline, lock, reviewer packages, and policy; never re-resolved on continuation. For `diff`, this Snapshot is also the Campaign's immutable Base, so use the integration branch or merge base such as `origin/main`, not `HEAD`. |
| `--uncommitted` | Capture tracked and untracked-not-ignored worktree content behind a monitored two-pass boundary, then build an isolated synthetic Git head without writing candidate objects. Changed gitlinks and unsafe parent symlinks fail closed. |
| `--restart-round` | Explicitly supersede an incomplete Round's immutable Subject and input sets with a newly captured head under the next epoch. |
| `--focus "text"` | Pinned Campaign focus appended to every reviewer prompt; changing it requires a new Campaign. |
| `--repo DIR` | Repo to review (default `.`). |
| `--pipeline FILE` | Default `.review/pipelines/heavy.toml`. |
| `--state DIR` | Override the state directory (default `.review/runs/<campaign>`). |
| `--timeout-secs N` | Per-reviewer-invocation timeout (default 1800). |

`reviewctl ledger --campaign NAME` prints the compact findings ledger;
`reviewctl ledger --campaign NAME --long` includes each finding's body and fix;
`reviewctl show --campaign NAME KEY` prints its complete attached reports and history;
`reviewctl report --campaign NAME --format md` emits the canonical closing report;
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
