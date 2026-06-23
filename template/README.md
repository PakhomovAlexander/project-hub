# {{PROJECT_NAME}} — Project Hub

<!-- TEMPLATE: the hub's front door. Customize the intro, the key-repos table (or delete it
     for a single-repo project), and the "where to read next" list. Remove TEMPLATE comments. -->

The cockpit for **{{PROJECT_NAME}}** — {{PROJECT_TAGLINE}}. Project management and the full
workflow across the key repos, driven from one place.

This repo holds the **docs and the controls**, not the product code. The product code lives
in the key repos below; this hub links them into [`repos/`](repos/) so you can read, build,
review, and ship them without leaving the cockpit. Read [`CONTEXT.md`](CONTEXT.md) first.

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
├── CLAUDE.md              # working agreement for agents in this repo
├── TEAM.md                # people ↔ GitHub ↔ ownership
├── Makefile · scripts/    # link / clone / status the key repos
├── repos.manifest         # the list of repos this hub coordinates
├── docs/
│   ├── index.md           # map of all docs
│   ├── plan.md            # the master plan
│   ├── tracker.md         # live status board
│   ├── issue-lifecycle.md # how the backlog moves
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

## Where to read next

1. [`CONTEXT.md`](CONTEXT.md) — the language.
2. [`docs/plan.md`](docs/plan.md) — the master plan.
3. [`docs/tracker.md`](docs/tracker.md) — what's in flight right now.
4. [`CLAUDE.md`](CLAUDE.md) — the working agreement before you change anything.
