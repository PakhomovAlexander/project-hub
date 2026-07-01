# This repo is a template, not a project

This is the **Project Hub template** — a skeleton for scaffolding a project cockpit, not a
project itself.

**If you were asked to "set up a project hub" (or "set up `<X>`"): follow
[`SETUP.md`](SETUP.md).** It is the runbook — read it top to bottom, interview the user, and
generate a customized hub from [`template/`](template/).

> **Using an agent other than Claude Code?** [`AGENTS.md`](AGENTS.md) is the vendor-neutral
> copy of this pointer — same template, same runbook (`SETUP.md`).

- The hub skeleton lives in [`template/`](template/). Everything there uses `{{TOKEN}}`
  placeholders and `<!-- TEMPLATE: … -->` guidance comments meant to be filled and removed.
- Don't "fix" the placeholders in place — they're inputs. The generated hub is a *copy* of
  `template/` with the placeholders resolved, created in a new directory.
- This file, [`AGENTS.md`](AGENTS.md), and `README.md` describe the *template*; they are
  **not** copied into a generated hub. (A generated hub gets its own `AGENTS.md` + `CLAUDE.md`
  from `template/`.)
