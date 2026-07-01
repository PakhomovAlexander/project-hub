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
