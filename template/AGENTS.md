# Working agreement — {{PROJECT_NAME}} Project Hub

<!-- TEMPLATE: The operating contract for ANY agent working in this hub. This file is the
     single source of truth for the rules: Codex, Cursor, Gemini CLI, … read AGENTS.md
     natively, and Claude Code loads it through the @AGENTS.md import in CLAUDE.md — so
     never fork the rules into per-vendor files. Keep it SHORT and CONCRETE — rules an
     agent can actually follow and you could test. Delete sections that don't apply (e.g.
     the linked-repos section for a single-repo project). Remove these TEMPLATE comments
     as you fill it in. -->

This repo is the **cockpit** for {{PROJECT_NAME}}: it holds the docs and controls; the
product code lives in the linked repos under `repos/`. Read [`CONTEXT.md`](CONTEXT.md) for
the shared language before doing anything, [`docs/index.md`](docs/index.md) for the map of
everything, and [`docs/tracker.md`](docs/tracker.md) for what's in flight right now.

## The repos under `repos/` are live working copies

<!-- TEMPLATE: DELETE this section for a single-repo project — but keep the worktree bullet
     (parallel agents on the hub's own docs still collide on one checkout); move it up. -->

`repos/<name>` is a **symlink to the real clone** in `{{CLONE_WORKSPACE}}`. Editing a file
there edits that working copy **on whatever branch it currently has checked out**.

- Run `make status` first — know each repo's branch and dirty state before you touch it.
- Don't switch branches or stash in a linked repo without saying so; the user may have
  in-flight work there (feature branches, uncommitted changes).
- These are separate git repos. Commit/push happens **inside** `repos/<name>`, against
  `{{ORG}}/<name>` — not from the hub. The hub commits only its own docs/tooling.
- **Running several agents over the hub at once?** Give each its own `git worktree` — one
  checkout has a single branch + index, so parallel agents collide. See
  [`docs/parallel-agents.md`](docs/parallel-agents.md) (`make worktree` / `make worktree-repo`).

## Invariants (don't break these)

<!-- TEMPLATE: The 2–6 hard rules specific to THIS project — the ones that, if violated,
     cause real damage or rework. Make each concrete and checkable. Examples of the *shape*
     (replace entirely): a naming/isolation rule, a security boundary, a "never touch X",
     a routing/deploy rule. Link each to its ADR where one exists. -->

- **{{Invariant 1}}** ({{ADR-000X}}): {{the rule, stated concretely, with the exact
  boundary — what's forbidden and what's explicitly exempt.}}
- **{{Invariant 2}}**: {{rule.}}
- **{{Invariant 3}}**: {{rule.}}

## PR / CI discipline

After any push or PR, **always** check CI and don't call it done until green:

```
gh pr view <number> --repo {{ORG}}/<repo> --json statusCheckRollup
```

- CI running → wait and recheck. CI failed → read logs, fix, push, wait for green.
- **Always paste the full PR URL** (`https://github.com/{{ORG}}/<repo>/pull/<n>`), not just
  the number, so it's clickable.

## Verification

Run what you build before reporting it done. Type-checks and tests verify code correctness,
not feature correctness — if you can't run it, say so explicitly rather than claiming
success. <!-- TEMPLATE: add project-specific dry-run guidance, e.g. for infra prefer
`terraform plan` / `helm template` / `kubectl --dry-run` over asserting an outcome. -->

## Changes land as code

<!-- TEMPLATE: KEEP this for a project whose live state is reconciled from git (GitOps/ArgoCD,
     Terraform, declarative deploys) — out-of-band edits get reverted, so "done" must mean
     merged code. DELETE it for a project where this doesn't apply. Promote it to an ADR if
     it's a load-bearing decision. -->

Git is the source of truth for {{the reconciled surface — infra / deploy config / …}}. A
change isn't done until it's **expressed as code and merged**. Debugging live out-of-band
(a console edit, `kubectl edit`, an admin API) is fine **to confirm a fix** — but that's a
**probe, not the change**: the next reconcile/redeploy reverts it. Backfill the probe into
code and land it via PR; its issue isn't `status:merged` until that PR is.

## Issue lifecycle

<!-- TEMPLATE: adjust to where the backlog actually lives. -->

Backlog is {{GitHub Issues / Jira / docs/tracker.md}}. **Don't close an issue when its PR
merges** — mark it `status:merged`, then close only after a human verifies it in prod. See
[`docs/issue-lifecycle.md`](docs/issue-lifecycle.md).

## Keeping docs honest

If you hit a factual error here (stale path, wrong command, a status that's moved), fix it
in the same change — especially [`docs/tracker.md`](docs/tracker.md), which is only useful
if it's current. Don't open cosmetic/rewording PRs.

Learned something durable — a gotcha, a decision, a status change? It belongs **in the hub
docs** (the tracker, an ADR, the repo's reference doc), not in your agent's private memory.
The hub is the project's shared memory: versioned, reviewable, and visible to every agent
and human. Private memory dies with your machine.

## Skills — the hub's processes, executable

Recurring workflows live as skills in [`.agents/skills/`](.agents/skills/) (open Agent
Skills format; Claude Code reads the same files via the `.claude/skills` link): `/adr`,
`/tracker`, `/resume`, `/onboard-repo`, `/verify`, `/update-hub`, `/self-review-heavy`
(staged multi-model review of a substantial change, pre-PR — expensive, use
deliberately). Prefer invoking them over improvising the same workflow from memory.

## Guardrails

`.claude/settings.json` and `.claude/hooks/` make Claude Code prompt a human before
prod-affecting or destructive commands (pushes, cloud CLIs, recursive deletes, deploys,
publishing). **Other agents don't get that net automatically** — apply the same rule
yourself: ask before running any command family listed in
`.claude/hooks/ask-before-risky-commands.sh`.
