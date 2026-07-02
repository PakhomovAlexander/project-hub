# Running several agents over the hub at once

<!-- TEMPLATE: this pattern is generic — keep it. For a SINGLE-REPO hub, keep the
     "Hub workspace" section (parallel agents on the hub's own docs still collide on
     one checkout) but delete "Linked repo workspace" (there are no repos/* to worktree),
     and drop the `worktree-repo` line from the Makefile. Remove these TEMPLATE comments. -->

You can point multiple `claude` processes at this hub in parallel — but a single
checkout has **one** working tree, index and HEAD, so two agents that switch
branches or stage files will clobber each other. Give every agent its own
**git worktree**: a separate directory + branch + index backed by the same
object store (cheap — no re-clone). Git refuses to check out one branch in two
worktrees, so the collision is structurally impossible, not just discouraged.

## Two kinds of workspace

Pick the one that matches the agent's task.

### Hub workspace — for the hub's own docs / tooling

```bash
make worktree NAME=tracker          # -> ../{{PROJECT_NAME}}-wt-tracker on branch agent/tracker (off main)
make worktree NAME=docs BASE=main
```

The worktree is placed as a **sibling** of the hub (named `<hub-dir>-wt-<name>`), so
the relative `repos/*` symlinks still resolve into `{{CLONE_WORKSPACE}}`. Launch the
agent in it: `cd ../{{PROJECT_NAME}}-wt-tracker && claude`.

### Linked repo workspace — for editing one linked repo

<!-- TEMPLATE: DELETE this section for a single-repo hub. -->

The `repos/<name>` symlinks all point at **one shared clone** per repo, so
worktreeing the *hub* does **not** isolate the product code: two agents both
editing `repos/{{repo-a}}/...` still collide. When two agents must edit the
**same** linked repo at once, give each its own worktree of that repo:

```bash
make worktree-repo NAME=tracker REPO={{repo-a}}   # -> {{CLONE_WORKSPACE}}/{{repo-a}}-wt-tracker
```

That agent then edits the repo **in that directory** — not via
`repos/{{repo-a}}`, which is the shared clone. Commit there against
`{{ORG}}/<repo>`, as usual for linked repos. The branch bases off the repo's own
default (`main`, `master`, …); override with `BASE=`.

If two agents touch **different** linked repos, you don't need this — the shared
clones don't collide. Just assign one repo per agent.

## Lifecycle

```bash
make worktree-ls                  # every agent worktree, hub + linked
make worktree-rm NAME=tracker     # remove tracker's worktrees, prune, drop the branch if merged
```

`worktree-rm` refuses to throw away uncommitted work; once the agent's PR is
pushed/merged, re-run — or `FORCE=1 make worktree-rm NAME=tracker` to discard.

## Rules of thumb

- **One worktree per agent** — never two agents in the same directory.
- **One writer per linked repo**, unless you've given them separate worktrees.
- Branch per agent (`agent/<name>`), PR per task — same discipline as the rest of the hub.
- Tear down when the PR merges, so stale worktrees don't pile up (`make worktree-ls` to audit).
- **`docs/tracker.md` is the hub's hottest file.** Pull/rebase right before editing it and
  keep tracker updates in their own small commits, so parallel agents' PRs don't conflict.
- **Serialize git operations across worktrees of one repo.** Worktrees share a single
  object store — simultaneous `fetch`/`gc`/`rebase` from two agents can corrupt shared
  metadata. Stagger them.

## Hub context doesn't follow you into a linked repo

`AGENTS.md` / `CLAUDE.md` and the `.claude/` guardrails load from the directory an agent is
**launched in**. A session started inside a linked repo — or its private worktree from
`make worktree-repo` — gets that repo's own agent files, **not** the hub's working
agreement and **not** the hub's risky-command gate. Two consequences:

- Give each linked repo a thin `AGENTS.md` pointing back at this hub (the setup runbook
  offers to create these), so the invariants travel.
- Prefer launching agents from the hub (or a hub worktree) when a task spans repos.

## Native alternatives

Some agent CLIs now manage worktrees themselves — e.g. Claude Code's background agents run
each task in an auto-created worktree. These scripts stay useful where that doesn't reach:
they're vendor-neutral, they cover the shared-clone linked-repo case (`make worktree-repo`),
and they give you explicit lifecycle control (`make worktree-ls` / `make worktree-rm`).
