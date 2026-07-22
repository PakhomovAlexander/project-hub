**Paste this into Claude Code** — hit the copy button, paste, and it scaffolds your hub:

```
Create a project hub from this template: https://github.com/PakhomovAlexander/project-hub
```

# Project Hub — a template for running a project with Claude Code

A **Project Hub** is one repo that becomes the *cockpit* for your project: shared language,
the plan, the decisions, the live status, and the controls — all in one place an agent and a
human can both operate from. The product code stays in its own repo(s); the hub links them
in and drives planning, review, and ops from above.

This template is a battle-tested shape for that cockpit, designed so you can hand it to
**Claude Code** and have it scaffolded for you in minutes.

## The 30-second pitch

Most "AI in the repo" setups give the agent a `CLAUDE.md` and hope. A hub goes further:

- **`CONTEXT.md`** — a real glossary (ubiquitous language) so the agent uses *your* words.
- **`AGENTS.md`** — the working agreement: invariants the agent must never break, plus
  PR/CI, verification, and doc-honesty discipline. It's the vendor-neutral standard file,
  so Codex, Cursor, Gemini CLI & co. load it natively.
- **`CLAUDE.md`** — a thin adapter importing `AGENTS.md` + `CONTEXT.md`, so Claude Code
  deterministically loads the same rules *and* the glossary — one source of truth, no drift.
- **`.agents/skills/`** — the hub's processes as executable skills (open Agent Skills
  format): `/adr`, `/tracker`, `/resume`, `/onboard-repo`, `/verify`, `/update-hub`,
  `/self-review-heavy` (a staged multi-model pre-PR review pipeline: local gate → deep
  architecture/perf review → cross-model second opinion, iterated to convergence on a
  findings ledger, with benchmark demands for performance claims).
- **`docs/adr/`** — decisions recorded with options + consequences, superseding over time.
- **`docs/tracker.md`** — a living status board: what's true *right now*, dated — and a
  session-start hook that briefs every new session on it (and flags it when stale).
- **`docs/workstreams/`** — deep design docs for in-flight work, with "resume here" sections.
- **`docs/service-catalog.md`** — a tiered, agent-facing map of every service/repo + doc
  status (each repo doc leads with its dev loop), so a session looks a thing up instead of
  re-deriving it.
- **`scripts/repos.sh` + `repos.manifest`** — link many live repos into `repos/` as symlinks.
- **`scripts/worktree.sh`** — run several agents over one hub at once, each in its own git
  worktree, without branch/index collisions.
- **`.claude/settings.json` + hooks** — layered guardrails: safe hub commands pre-allowed,
  risky families prompt first (declarative `ask` rules backed by a wrapper-aware hook that
  never widens your own permission config).
- **`.github/` docs CI + `scripts/verify.sh`** — markdownlint + an offline link check on
  every PR, and the same checks runnable locally, so the docs can't silently rot.

The result: an agent can pick up cold work, speak your domain, respect your rules, not nuke
prod, and run alongside a dozen of its peers — and a human can read the whole project's state
from one folder.

## Use it (the "send a link" flow)

Point Claude Code at this repo and say what you want:

> *"Set up a project hub for **Acme** using this template: `<link-to-this-repo>`.
> It's a real-time collaboration app across three repos in the `acme-inc` org."*

Claude reads [`SETUP.md`](SETUP.md) — the agent runbook baked into this template — then
**interviews you** for the specifics (name, repos, invariants, environments, team, which
commands should prompt before running), **generates a customized hub** in a new directory,
wires up the repo links, and verifies it.

You can also drive it locally:

```bash
git clone <link-to-this-repo> project-hub-template
cd project-hub-template
# then, in Claude Code:  "Follow SETUP.md and scaffold a hub for <my project>."
```

## Keep a hub current

The template keeps improving after you scaffold. Every generated hub records where it
came from in `.hub-meta.yml` (template URL + commit + your setup answers), so later —
inside the hub — you can just say:

> *"Update this hub from its template."* (or run the `/update-hub` skill)

The agent follows [`UPDATE.md`](UPDATE.md): it diffs `template/` since the recorded
commit and re-applies the changes with your hub's own values — machinery (scripts, hooks,
skills, CI) updates cleanly; the docs you've authored are never overwritten.

## What you get

```
your-project-hub/
├── CONTEXT.md              # shared language / glossary — read first
├── AGENTS.md              # the working agreement — canonical rules for ANY agent
├── CLAUDE.md              # thin Claude Code adapter: imports AGENTS.md + CONTEXT.md
├── README.md              # the hub's own front door
├── TEAM.md                # people ↔ GitHub ↔ ownership (optional)
├── .hub-meta.yml          # provenance: template url + sha + answers — powers /update-hub
├── Makefile · scripts/    # link/status the repos · worktrees · verify.sh self-check
├── repos.manifest         # the list of repos this hub coordinates
├── .agents/skills/        # /adr /tracker /resume /onboard-repo /verify /self-review-heavy (any agent)
├── .claude/               # allow/ask permission lists + hooks (session brief, risky-cmd gate)
├── .github/workflows/     # docs CI: markdownlint + offline link check
├── .markdownlint-cli2.jsonc # light, high-signal Markdown rules
├── docs/
│   ├── index.md          # map of all docs
│   ├── plan.md           # the master plan (scope, workstreams, risks, decisions)
│   ├── tracker.md        # live status board
│   ├── service-catalog.md# every service/repo + doc status + the doc standard
│   ├── issue-lifecycle.md# how the backlog moves
│   ├── parallel-agents.md# running several agents at once via git worktrees
│   ├── adr/              # architecture decision records (+ a seed ADR + a template)
│   ├── workstreams/      # in-flight work: design + acceptance + resume-here
│   └── repos/            # one Tier-1 reference per linked repo (dev loop first)
└── repos/                # symlinks into your real clones (gitignored)
```

Single-repo project? The setup drops the linking machinery — you keep the docs, the
invariants, the ADRs, and the safety hook.

## What's in this template repo

- [`SETUP.md`](SETUP.md) — the runbook an agent follows to scaffold a hub (both `AGENTS.md`
  and `CLAUDE.md` point here). Read it to see exactly what the agent will do.
- [`UPDATE.md`](UPDATE.md) — the runbook an agent follows to bring an already-generated hub
  up to date with this template: a three-way merge driven by the hub's `.hub-meta.yml`,
  updating machinery without overwriting the hub's own docs.
- [`template/`](template/) — the hub skeleton (placeholders + inline guidance) that gets
  copied and customized into your new hub.
- [`scripts/verify-hub.sh`](scripts/verify-hub.sh) — run it against a generated hub to catch
  leftover placeholders, broken internal links (including links into gitignored `repos/`),
  and non-executable hooks before calling setup done. The same verifier ships *inside*
  every hub as `scripts/verify.sh`.
- [`tests/`](tests/) + [`.github/workflows/template-ci.yml`](.github/workflows/template-ci.yml)
  — the template tests itself on every PR: shellcheck, a table-driven test of the safety
  hook, a full scaffold-then-verify smoke run, and an update drill (scaffold at v1 →
  evolve the template → apply the UPDATE.md mechanics → verify).

## Why it works

The patterns here came from running a real multi-repo product launch entirely through a
hub. The agent could resume cold work, respect hard invariants, keep a truthful status
board, and operate across a dozen repos without losing the plot — because the cockpit made
the project's *language, decisions, and state* first-class, not tribal knowledge.

This template is generic and project-agnostic. It contains **no** details from any specific
project — just the shape. Make it yours.

## License

[MIT](LICENSE). Use it, fork it, share it.
