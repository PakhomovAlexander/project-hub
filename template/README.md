# {{PROJECT_NAME}} — Project Hub

<!-- TEMPLATE: the hub's front door. Customize the intro, the key-repos table (or delete it
     for a single-repo project), and the "where to read next" list. Remove TEMPLATE comments. -->

The cockpit for **{{PROJECT_NAME}}** — {{PROJECT_TAGLINE}}. Project management and the full
workflow across the key repos, driven from one place.

This repo holds the **docs and the controls**, not the product code. The product code lives
in the key repos below; this hub links them into `repos/` (gitignored — recreated by
`make repos`) so you can read, build, review, and ship them without leaving the cockpit.
Read [`CONTEXT.md`](CONTEXT.md) first.

## Key repos

<!-- TEMPLATE: DELETE this section for a single-repo project. Otherwise list the repos this
     hub coordinates; keep it in sync with repos.manifest. -->

`make repos` symlinks these from the workspace (`{{CLONE_WORKSPACE}}`) into `./repos/`. The
real clones keep their own branches and working state — the hub never edits them behind your
back.

| Repo | Role | GitHub |
|------|------|--------|
| `{{repo-a}}` | {{what it is}} | [{{ORG}}/{{repo-a}}](https://github.com/{{ORG}}/{{repo-a}}) |
| `{{repo-b}}` | {{what it is}} | [{{ORG}}/{{repo-b}}](https://github.com/{{ORG}}/{{repo-b}}) |

## Layout

```
{{PROJECT_NAME}}-hub/
├── CONTEXT.md              # shared language / glossary (read this first)
├── README.md              # you are here
├── AGENTS.md              # the working agreement — canonical rules for ANY agent
├── CLAUDE.md              # thin Claude Code adapter: imports AGENTS.md + CONTEXT.md
├── TEAM.md                # people ↔ GitHub ↔ ownership
├── Makefile · scripts/    # link/status the key repos · worktrees · verify.sh self-check
├── repos.manifest         # the list of repos this hub coordinates
├── .agents/skills/        # executable hub processes: /adr /tracker /resume … (any agent)
├── .claude/               # settings (allow/ask lists) + hooks (session brief, risky-cmd gate)
├── docs/
│   ├── index.md           # map of all docs
│   ├── plan.md            # the master plan
│   ├── tracker.md         # live status board
│   ├── service-catalog.md # every service & repo + doc status, the doc standard
│   ├── issue-lifecycle.md # how the backlog moves
│   ├── parallel-agents.md # run several agents at once, each in its own worktree
│   ├── adr/               # architecture decision records
│   ├── workstreams/       # in-flight work
│   └── repos/             # per-repo overviews
└── repos/                 # symlinks into {{CLONE_WORKSPACE}} (gitignored)
```

## Getting started

```bash
make repos        # link the key repos into ./repos (clone what's missing)
make status       # see what branch each repo is on and whether it's dirty
make list         # the repo manifest
```

## Running several agents at once

A single checkout has one branch + index, so parallel agents collide. Give each its own
git worktree — see [`docs/parallel-agents.md`](docs/parallel-agents.md):

```bash
make worktree NAME=tracker    # isolated hub workspace on branch agent/tracker
make worktree-ls              # list every agent worktree
make worktree-rm NAME=tracker # tear it down when the PR merges
```

## Where to read next

1. [`CONTEXT.md`](CONTEXT.md) — the language.
2. [`docs/plan.md`](docs/plan.md) — the master plan.
3. [`docs/tracker.md`](docs/tracker.md) — what's in flight right now.
4. [`AGENTS.md`](AGENTS.md) — the working agreement before you change anything.
