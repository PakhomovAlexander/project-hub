# This repo is a template, not a project

This is the **Project Hub template** — a skeleton for scaffolding a project cockpit, not a
project itself.

**If you were asked to "set up a project hub" (or "set up `<X>`"): follow
[`SETUP.md`](SETUP.md).** It is the runbook — read it top to bottom, interview the user, and
generate a customized hub from [`template/`](template/).

- The hub skeleton lives in [`template/`](template/). Everything there uses `{{TOKEN}}`
  placeholders and `<!-- TEMPLATE: … -->` guidance comments meant to be filled and removed.
- Don't "fix" the placeholders in place — they're inputs. The generated hub is a *copy* of
  `template/` with the placeholders resolved, created in a new directory.
- This file and `README.md` describe the *template*; they are **not** copied into a
  generated hub.
