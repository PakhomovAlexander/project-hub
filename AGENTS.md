# AGENTS.md

This repository is the **Project Hub template** — a skeleton for scaffolding a project
cockpit, not a project itself. It is agent-agnostic: any coding agent can use it.

**Asked to "set up a project hub" (or "set up `<X>`")? Follow [`SETUP.md`](SETUP.md)** — the
runbook. Read it top to bottom, interview the user, and generate a customized hub from
[`template/`](template/).

**Asked to "update a hub" that was generated earlier? Follow [`UPDATE.md`](UPDATE.md)** —
the update runbook: a three-way merge that applies what changed in `template/` since the
hub's recorded version (`.hub-meta.yml`) without overwriting the hub's own content.

- The skeleton in [`template/`](template/) uses `{{TOKEN}}` placeholders and
  `<!-- TEMPLATE: … -->` notes meant to be filled and removed. Don't "fix" them in place —
  they're inputs; the generated hub is a *copy* of `template/` with the placeholders resolved,
  created in a new directory.
- This file, `README.md`, and `CLAUDE.md` describe the *template* — they are **not** copied
  into a generated hub. A generated hub gets its own agent files from `template/` (both
  `AGENTS.md` and `CLAUDE.md`).

This file is canonical; `CLAUDE.md` imports it (`@AGENTS.md`) so Claude Code lands on the
same runbook as every other agent — the same single-source pattern a generated hub uses.
