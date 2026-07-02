# UPDATE — bring a generated hub up to date with this template

**You are an agent. Someone pointed you at a Project Hub that was generated from this
template and asked you to "update the hub" (or the hub's `/update-hub` skill sent you
here). This file is your runbook.** Read it top to bottom, then do it.

Your job: apply what changed in [`template/`](template/) since the hub was generated —
**without stomping anything the hub's owners have made their own**. A hub is not a fork
of this repo: at setup time tokens were resolved, guidance comments stripped, files
dropped, and content authored. So this is a **three-way merge** — *base* = the template
as the hub last saw it, *ours* = the hub today, *theirs* = the template now — and **you
are the merge engine**, applying judgment where `diff3` would dump conflict markers.

---

## 0. Ground rules

- **The hub owns its content.** `CONTEXT.md`, the plan, the tracker, ADRs, workstreams,
  invariants — authored by the hub's people. Never overwrite them; at most graft in a
  structural improvement. Machinery (scripts, hooks, skills, CI, lint config) is yours
  to update.
- **The hub's own rules bind you.** Its `AGENTS.md` is in force while you work — risky
  commands prompt, pushes go through the hub's normal flow, nothing lands behind the
  user's back. Work on a branch.
- **Report honestly.** Every hunk is *applied*, *merged*, or *skipped (and why)*. If the
  delta is empty, say "already current" and stop — don't invent work.

---

## 1. Read the hub's provenance

`.hub-meta.yml` at the hub root records everything you need: `template.url` +
`template.sha` (what to diff against), `layout` (single- vs multi-repo), `answers` (the
token values used at setup), and `dropped` (template files the hub deliberately removed).

**Older hub without `.hub-meta.yml`?** Fall back, then backfill:

- The base sha may be stamped at the bottom of the hub's `README.md`:
  `generated from project-hub@<short-sha>`.
- Answers are inferable from the hub itself: project name from `README.md`/`AGENTS.md`,
  org from `repos.manifest` or git remotes, workspace from `additionalDirectories` in
  `.claude/settings.json`. Ask the user for anything you can't infer — don't guess.
- No sha anywhere → ask roughly when the hub was created and use the template commit
  nearest that date as base; expect more judgment calls.
- **Write the reconstructed `.hub-meta.yml` as part of this update** (copy the shape
  from `template/.hub-meta.yml`), so the next update is clean.

## 2. Fetch the template and scope the delta

Clone `template.url` into a scratch directory — a **full clone**, you need history:

```bash
git clone <template.url> /tmp/hub-template && cd /tmp/hub-template
git log --oneline <sha>..HEAD -- template/   # the narrative: what changed and why
git diff <sha>..HEAD -- template/            # the delta you will apply
```

Read the log (and release/changelog notes between the two versions, if the template has
them) before the diff — commit messages carry migration intent that hunks don't.
Everything outside `template/` (this file, `SETUP.md`, the template's own README/tests)
never ships into hubs — ignore it.

Empty delta → report "already current", stop.

## 3. Reconstruct *base*

For each file you're about to touch, *base* is what the hub started from:
`git show <sha>:template/<path>` with the hub's `answers` substituted (and, where setup
strips them, the `<!-- TEMPLATE: … -->` guidance comments removed). Reconstruct it
per-file as needed — it's what lets you tell **consumer edits** from **template edits**.

Every hub file then has one of two states: **pristine** (ours == base — the owners never
touched it) or **customized** (ours ≠ base).

## 4. Apply, file by file

Map `template/<path>` → `<hub>/<path>`. For each path in the delta, in this order:

1. **In `dropped:`, or machinery the hub's `layout` excludes** (single-repo hubs have no
   `repos.manifest`, `scripts/repos.sh`, `docs/repos/`, `onboard-repo` skill, service
   catalog…) → **skip**, record it in your summary.
2. **New in the template** → copy in, resolve tokens from `answers` (today's date for
   `{{TODAY}}`), strip guidance comments the way `SETUP.md` §4 prescribes. A new token
   not in `answers`? Ask the user for just that value, then record it in `answers`.
3. **Deleted in the template** → hub copy pristine? Delete it. Customized? Keep it and
   flag the divergence — the owners may be relying on it.
4. **Changed, hub copy pristine** → take theirs, re-resolve tokens. This is the common
   case: most template evolution is machinery consumers never edit.
5. **Changed, hub copy customized** → merge with judgment:
   - *Machinery with owner-tuned lines* — `.claude/settings.json` (`permissions.ask`,
     `additionalDirectories`), the `RISKY_WORDS` line in
     `.claude/hooks/ask-before-risky-commands.sh`, `repos.manifest`: apply the template's
     changes **around** the owner's entries; never reset their lists to the defaults.
   - *Content* (`CONTEXT.md`, `AGENTS.md`, `README.md`, `TEAM.md`, `docs/**`): the hub's
     prose wins. Adopt only structural improvements — a new section the hub lacks, a
     fixed command, a corrected link — each as a surgical edit. Torn? Keep ours and note
     the template change in your summary instead.
   - `_template.md` scaffolds keep their guidance comments in hubs too — update them
     wholesale like machinery unless the hub customized them.

## 5. Finish and verify

- `chmod +x` everything under `scripts/` and `.claude/hooks/` — files you just added
  won't be executable.
- Run the hub's `scripts/verify.sh` — the **freshly updated** one, so new checks apply.
  Fix everything it flags.
- Bump `.hub-meta.yml`: `template.sha` → the sha you updated to; add or refresh an
  `updated: <date>` line under `template:`.
- Commit on a branch with a summary the owner can review in one read: applied / merged /
  skipped (each with why), plus any follow-ups only a human can decide. Open a PR if
  that's how the hub works; otherwise stop at the branch and say so.

## 6. Honesty bar

- Never claim a hunk landed that you skipped — the summary lists every skip.
- A template change that contradicts one of the hub's **invariants or ADRs** loses
  automatically; flag the conflict instead of applying it.
- Don't "helpfully" rewrite hub prose while you're in there. Update = template delta
  only; anything else is a separate PR the owner asked for.
