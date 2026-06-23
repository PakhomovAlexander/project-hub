# SETUP — scaffold a Project Hub from this template

**You are an agent. Someone pointed you at this repository and asked you to "set up a
project hub" (or "set up `<X>`"). This file is your runbook.** Read it top to bottom,
then do it. Everything you need is here.

Your job: turn the skeleton in [`template/`](template/) into a real, customized Project
Hub for the user's project — a single repo that becomes the *cockpit* for their work.

---

## 0. What a Project Hub is (build it in this spirit)

A Project Hub is **one repo that holds the docs and the controls for a project, not
(usually) the product code**. When a project spans several repos/services, the hub links
them in and drives planning, review, and ops from one place. When it's a single repo, the
hub is just the brain of that repo. Either way, these are the patterns that make it good —
preserve them as you fill things in:

- **Cockpit, not codebase.** The hub holds shared language, plans, decisions, status, and
  tooling. Product code lives in the linked repos (see `repos/`), or in this same repo if
  it's a one-repo project.
- **Ubiquitous language first** (`CONTEXT.md`). A glossary with crisp definitions, an
  *Avoid* list per term, the relationships between terms, and flagged ambiguities. Everyone
  (humans + agents) speaks the same words. This is the highest-leverage file — get it right.
- **Invariants** (`CLAUDE.md`). A short list of rules an agent must never break. Make them
  concrete and testable, not platitudes.
- **Decisions are recorded** (`docs/adr/`). Architecture Decision Records, each with the
  options considered and the consequences. Decisions supersede each other honestly over time.
- **A living status board** (`docs/tracker.md`). What's actually true *right now*, dated,
  including where reality has diverged from the plan. Worthless if stale — so it's a rule to
  keep it current.
- **Deep docs for in-flight work** (`docs/workstreams/`). Design + acceptance criteria +
  a "resume here" section, so work survives interruption and hand-off.
- **Repos are linked, not vendored** (`scripts/repos.sh`, `repos.manifest`). The hub
  symlinks live working copies; it never edits them behind the user's back.
- **Safe by default** (`.claude/`). A pre-tool hook asks before prod-affecting / destructive
  commands and auto-allows the rest.
- **Honesty discipline.** Verify before claiming done; fix stale docs in the same change;
  don't open cosmetic PRs.

Keep the voice **crisp, opinionated, and concrete**. No filler.

---

## 1. Get the template

If you don't already have these files locally:

```bash
git clone <this-repo-url> /tmp/project-hub-template
```

…or read them directly from the link the user gave you. Everything you copy comes from the
[`template/`](template/) subdirectory.

---

## 2. Interview the user

Ask only what the user hasn't already told you. **Batch the questions** (use your
question/prompt UI to ask several at once — don't drip one at a time). Use sensible
defaults and say what you assumed. Minimum set:

1. **Identity** — the project name / wordmark (and any **casing rule**, e.g. "always
   lowercase"); a one-line description of what it is; what kind of project it is
   (single repo · multi-repo product · infra/platform).
2. **Linked repos** — does this project span multiple repos?
   - If **yes**: the GitHub **org/owner**; the list of repos (for each: the name you'll
     `cd` into, the actual clone directory name if different, the GitHub repo to clone, and
     a kind tag like `service`/`infra`/`web`/`lib`); and **where the real clones live**
     (usually a sibling workspace directory).
   - If **no** (single repo): skip the linking machinery — drop `repos/`, `repos.manifest`,
     `scripts/repos.sh`, and the `repos` targets from the `Makefile`. Say you did.
3. **Invariants** — 2–6 hard rules agents must never break (naming/brand isolation,
   security boundaries, "never touch X", registry/deploy routing, etc.). If none yet, leave
   a clearly-marked placeholder and move on.
4. **Surfaces** (optional) — environments, domains, registries, accounts. Only if relevant.
5. **Backlog** — where issues live (GitHub Issues · Jira · a tracker file) and any
   lifecycle convention (e.g. "don't close on merge; close after prod verification").
6. **Team** (optional) — people ↔ GitHub handles ↔ areas of ownership, and a default owner.
7. **Risky commands** — which command families should *prompt before running*. Offer the
   default set (`git push`, `aws`, `gcloud`, `az`, `kubectl`, `helm`, `terraform`,
   `terragrunt`, `docker push`) and let them add/remove.
8. **Known decisions** — any architectural decisions already made, to seed as ADRs.

---

## 3. Create the hub directory

Pick a location (ask if unclear; default: a sibling of the project's code workspace, the
way a cockpit sits next to the planes). Copy the **contents of `template/`** into it —
*not* this `SETUP.md` or the template's own `README.md`/`CLAUDE.md` (those describe the
template, not the hub). Then `git init` it as its own repo.

---

## 4. Generate the files

Work through the copied skeleton and make it real:

- **Substitute every placeholder** (the `{{TOKEN}}` list in §6) across all files.
- **`CONTEXT.md`** — write the real glossary. One entry per core term: definition, an
  *Avoid* list, then Relationships, an Example dialogue, and Flagged ambiguities. This is
  the file to spend the most care on. Delete the instructional `<!-- … -->` notes as you go.
- **`CLAUDE.md`** — fill the invariants, the linked-repos rules (or delete that section for
  a single-repo project), PR/CI discipline, and verification/issue-lifecycle/doc-honesty
  sections. Keep it short.
- **`docs/plan.md`** — the master plan: goal, scope (in/out), workstreams, timeline,
  risks, a decision register. Scale to the project; cut sections that don't apply.
- **`docs/tracker.md`** — seed the live board: today's date, the workstreams from the plan,
  and any known in-flight items. Mark unknowns `TBD`, don't invent status.
- **`repos.manifest`** — one line per linked repo (`canonical:clone_dir:github_repo:kind`),
  matching what the user gave you. (Delete if single-repo.)
- **`docs/repos/`** — one short overview per linked repo from the `_template.md` shape:
  role, GitHub link, and anything project-specific an agent must know before touching it.
- **`docs/adr/`** — keep `0001-record-architecture-decisions.md` (it's generic and useful).
  Write one ADR per known decision using `_template.md`.
- **`.claude/hooks/ask-before-risky-commands.sh`** — set the command watchlist to the
  families the user named (edit the marked regex; defaults are sensible).
- **`TEAM.md`** — fill or delete, per the interview.
- **`README.md`** (the hub's own) — customize the intro, the key-repos table, and the
  "where to read next" list.

After filling a file, **remove the `<!-- TEMPLATE: … -->` guidance comments** from it.

---

## 5. Wire it up and verify

- Make the script executable: `chmod +x scripts/repos.sh`.
- If multi-repo: `make repos` (links/clones the repos), then `make status` (branches +
  dirty state). Report what linked and what's missing — don't claim success you didn't see.
- `git add -A && git commit` the initial hub (only if the user wants it committed).
- Give the user a short summary: what you created, what you assumed, and what's left `TBD`.

---

## 6. Placeholders

Replace every occurrence across the copied files:

| Token | Meaning | Example |
|-------|---------|---------|
| `{{PROJECT_NAME}}` | Project / product wordmark, in its correct casing | `acme` |
| `{{PROJECT_TAGLINE}}` | One sentence: what the project is | `A real-time collaboration app` |
| `{{ORG}}` | GitHub org / owner for the linked repos | `acme-inc` |
| `{{CLONE_WORKSPACE}}` | Dir (relative to the hub) holding the real clones | `../acme` |
| `{{HUB_REPO}}` | The hub's own `org/repo`, for the backlog (optional) | `acme-inc/hub` |
| `{{DEFAULT_OWNER}}` | Fallback owner GitHub handle | `octocat` |
| `{{TODAY}}` | Date stamp for the tracker snapshot | `2026-06-23` |

---

## 7. Quality bar (don't skip)

- **Strip every template-author example.** The generated hub must contain **zero** details
  from any other project. Grep the result for leftover `{{`, `TEMPLATE:`, and example
  strings before you finish.
- **Don't invent facts.** If you don't know a domain, an account, a status — write `TBD`
  and flag it. A confident-but-wrong hub is worse than an honest sparse one.
- **Respect the wordmark casing** the user gave you, everywhere user-facing.
- **Scale to the project.** A small project doesn't need 10 workstreams or 5 ADRs. Delete
  what doesn't earn its place; the skeleton is a menu, not a mandate.
- **Single-repo projects:** drop the linking machinery (§2.2) — don't ship dead tooling.

When you're done, the user should be able to open the hub and have a sharp, honest cockpit
for their project — and you (or any agent) should be able to operate in it from `CLAUDE.md`
+ `CONTEXT.md` alone.
