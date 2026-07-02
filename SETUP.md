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
- **Invariants** (`AGENTS.md`). A short list of rules an agent must never break. Make them
  concrete and testable, not platitudes.
- **Decisions are recorded** (`docs/adr/`). Architecture Decision Records, each with the
  options considered and the consequences. Decisions supersede each other honestly over time.
- **A living status board** (`docs/tracker.md`). What's actually true *right now*, dated,
  including where reality has diverged from the plan. Worthless if stale — so it's a rule to
  keep it current.
- **Deep docs for in-flight work** (`docs/workstreams/`). Design + acceptance criteria +
  a "resume here" section, so work survives interruption and hand-off.
- **A service catalog** (`docs/service-catalog.md`). For a multi-service product: one row
  per service (what it is, where it lives, doc status) plus a tiered doc standard, so agents
  look a thing up instead of re-deriving it. Drop it for a small single-repo hub.
- **Repos are linked, not vendored** (`scripts/repos.sh`, `repos.manifest`). The hub
  symlinks live working copies; it never edits them behind the user's back.
- **Parallel agents, isolated** (`scripts/worktree.sh`, `docs/parallel-agents.md`). Several
  agents over one hub collide on a single index/branch; each gets its own `git worktree`
  (`make worktree`). Works even single-repo (agents on the hub's own docs).
- **Safe by default, in layers** (`.claude/`). Declarative permission lists (safe hub
  commands pre-allowed, risky families set to *ask*) backed by a pre-tool hook that catches
  risky commands in wrapper forms — and otherwise stays neutral, never widening what the
  user's own permission rules would allow. A session-start hook injects a **hub brief**
  (tracker snapshot age + repo status) so every session opens situationally aware.
- **Agent-agnostic** (`AGENTS.md` + `CLAUDE.md`). The working agreement lives in **one**
  file — `AGENTS.md`, the vendor-neutral standard that Codex, Cursor, Gemini CLI & co. read
  natively. `CLAUDE.md` is a thin adapter that imports it (`@AGENTS.md`) along with the
  glossary (`@CONTEXT.md`), so Claude Code deterministically loads the same rules. Keep the
  rules single-sourced; never copy them into both.
- **Processes are executable** (`.agents/skills/`). The hub's recurring workflows — record
  an ADR, refresh the tracker, resume a workstream, onboard a repo, self-check — ship as
  skills in the open Agent Skills format (Claude Code reads the same files via the
  `.claude/skills` link).
- **Docs stay honest automatically** (`.markdownlint-cli2.jsonc`, `.github/workflows/docs-ci.yml`).
  markdownlint + an offline internal-link check on every PR — the continuous form of
  `scripts/verify.sh`, which also ships inside the hub for local runs (`/verify`).
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

## 1.5 Inspect the project *before* you interview

The fastest, least annoying setup comes from reading first and asking second. Before §2,
find the project's actual code and mine it — a single sibling repo, the repos in the org
the user named, or the repo they linked. Pull defaults from:

- **`hugo.toml` / `package.json` / `Cargo.toml` / `go.mod` / `*.tf`** — name, language, stack.
- **CI configs / Makefiles / package scripts** — each repo's **dev loop** (build · test ·
  lint · run), which feeds the Dev loop section of its `docs/repos/<name>.md`.
- **An existing `CONTEXT.md`, `CLAUDE.md`, `README.md`, `docs/adr/`, `backlog.md`** — the
  project may *already* have a glossary, invariants, decisions, and a backlog. Read them.
- **`git log` / `git remote`** — recent direction, the real org/owner, what's in flight.

Come to the interview with **proposed answers**, not blank questions ("I see this is a Hugo
site called X with these two ADRs — single-repo, yes?"). This is what turns a long
interrogation into a quick confirmation.

> **If the code repo already has these docs, do not blindly duplicate them.** A second,
> parallel `CONTEXT.md` / ADR set in the hub will drift from the original. For each, decide
> and say which: **reference** it (link to the repo's copy), **lift** it (move it up to the
> hub as the new home), or **supersede** it (hub owns it going forward; leave a pointer in
> the repo). Pick one per artifact — never two copies of the same truth.

---

## 2. Interview the user

Ask only what the user hasn't already told you (or what §1.5 didn't already answer).
**Batch the questions** (use your question/prompt UI to ask several at once — don't drip one
at a time). Use sensible defaults and say what you assumed. Minimum set:

1. **Identity** — the project name / wordmark (and any **casing rule**, e.g. "always
   lowercase"); a one-line description of what it is; what kind of project it is
   (single repo · multi-repo product · infra/platform).
2. **Linked repos** — does this project span multiple repos?
   - If **yes**: the GitHub **org/owner**; the list of repos (for each: the name you'll
     `cd` into, the actual clone directory name if different, the GitHub repo to clone, a
     kind tag like `service`/`infra`/`web`/`lib`, and its **dev-loop commands** — build /
     test / lint / run; propose what you mined in §1.5); and **where the real clones live**
     (usually a sibling workspace directory).
   - If **no** (single repo): skip the linking machinery — drop `repos/`, `repos.manifest`,
     `scripts/repos.sh`, and the `repos` targets from the `Makefile`. Say you did.
3. **Invariants** — 2–6 hard rules agents must never break (naming/brand isolation,
   security boundaries, "never touch X", registry/deploy routing, etc.). If none yet, leave
   a clearly-marked placeholder and move on.
4. **Surfaces** (optional) — environments, domains, registries, accounts. Only if relevant.
5. **Backlog** — where issues live (GitHub Issues · Jira · a tracker file) and any
   lifecycle convention (e.g. "don't close on merge; close after prod verification").
   If it's Jira/Linear/another tool with an MCP server, offer to add a project-scoped
   `.mcp.json` so agents get the backlog as tools (GitHub needs none — `gh` covers it).
6. **Team** (optional) — people ↔ GitHub handles ↔ areas of ownership, and a default owner.
7. **Risky commands** — which command families should *prompt before running*. Offer the
   default set (`git push`, `aws`, `gcloud`, `az`, `kubectl`, `helm`, `terraform`,
   `terragrunt`, `docker push`) and let them add/remove. The answer lands in **two synced
   places**: `RISKY_WORDS` in the hook and `permissions.ask` in `.claude/settings.json`.
8. **Known decisions** — any architectural decisions already made, to seed as ADRs.
9. **Linked-repo pointers** (multi-repo only) — offer to add a thin `AGENTS.md` to each
   linked repo, via that repo's normal PR flow, so the hub's invariants travel with agents
   launched inside those repos (see §5 for the shape).

---

## 3. Create the hub directory

Pick a location (ask if unclear; default: a sibling of the project's code workspace, the
way a cockpit sits next to the planes). Copy the **contents of `template/`** into it with
`cp -a template/. <hub-dir>` (or `rsync -a template/ <hub-dir>/`) — `-a` keeps the dotfiles
(`.agents/`, `.claude/`, `.github/`, `.markdownlint-cli2.jsonc`, `.gitignore`) **and**
preserves the `.claude/skills → ../.agents/skills` symlink, both of which a plain
`cp template/*` glob destroys. Don't copy this `SETUP.md`, `UPDATE.md`, or the template's
own root `README.md`/`CLAUDE.md`/`AGENTS.md` (those describe the template, not the hub —
the hub gets its own from inside `template/`; they're outside `template/`, so the `cp -a`
above already excludes them). Then `git init` it as its own repo. (Windows, where symlinks may
materialize as text files: replace `.claude/skills` with a real copy of `.agents/skills`.)

---

## 4. Generate the files

Work through the copied skeleton and make it real:

- **Substitute every placeholder** (the `{{TOKEN}}` list in §6) across all files.
- **`CONTEXT.md`** — write the real glossary. One entry per core term: definition, an
  *Avoid* list, then Relationships, an Example dialogue, and Flagged ambiguities. This is
  the file to spend the most care on. Delete the instructional `<!-- … -->` notes as you go.
- **`AGENTS.md`** — the working agreement, canonical for **every** agent. Fill the
  invariants, the linked-repos rules (or delete that section for a single-repo project),
  and point the issue-lifecycle line at the real backlog. Keep it short (aim well under
  200 lines) — anything procedural belongs in a skill, not here.
- **`CLAUDE.md`** — leave it thin: keep the `@AGENTS.md` + `@CONTEXT.md` imports at the
  top, resolve the placeholders, and that's it. The rules live in `AGENTS.md` only, never
  duplicated here. (Single-repo: trim the linked-clones phrase from the guardrails bullet.)
- **`.agents/skills/`** — the six skills are generic; keep them as-is. Single-repo
  project: delete `onboard-repo/` (but keep `update-hub/` — it's how the hub takes
  template upgrades later). If the team has other recurring processes, add one skill
  per process (a directory + `SKILL.md`, `name` matching the directory).
- **`.claude/settings.json`** — resolve `{{CLONE_WORKSPACE}}` in
  `permissions.additionalDirectories` (single-repo: delete that key and the
  `make`/`repos.sh` entries in `permissions.allow`). Mirror the user's risky families into
  `permissions.ask`, kept in sync with the hook's `RISKY_WORDS`.
- **`.hub-meta.yml`** — the hub's provenance, read by `/update-hub` when the template
  improves later (see [`UPDATE.md`](UPDATE.md)). Resolve `{{TEMPLATE_URL}}` (this
  template repo's clone URL) and `{{TEMPLATE_SHA}}` (its `git rev-parse --short HEAD`),
  set `layout:`, keep `answers:` matching what the interview settled (delete rows that
  don't apply), and list in `dropped:` **every** template file you remove during setup —
  single-repo trims, a deleted `TEAM.md`, a skipped catalog — so updates skip them too.
- **`.mcp.json`** (only if the user opted in at §2.5) — a project-scoped MCP config at the
  hub root wiring the backlog tool, e.g.
  `{ "mcpServers": { "<backlog>": { "type": "http", "url": "<the tool's MCP endpoint>" } } }`.
  Don't ship one for GitHub-backed backlogs — `gh` already covers them.
- **`docs/plan.md`** — the master plan: goal, scope (in/out), workstreams, timeline,
  risks, a decision register. Scale to the project; cut sections that don't apply.
- **`docs/tracker.md`** — seed the live board: today's date, the workstreams from the plan,
  and any known in-flight items. Mark unknowns `TBD`, don't invent status.
- **`repos.manifest`** — one line per linked repo (`canonical:clone_dir:github_repo:kind`),
  matching what the user gave you. (Delete if single-repo.)
- **`docs/repos/`** — one Tier-1 reference per linked repo from the `_template.md` shape:
  role, GitHub link, deploy target, and anything project-specific an agent must know before
  touching it. (Delete the directory for a single-repo project.)
- **`docs/service-catalog.md`** — for a multi-service product, seed the catalog with the
  linked repos/services (what each is, where it lives, doc status ☐) and keep the doc
  standard + rollout plan. **Delete it for a small single-repo hub** — don't ship an empty
  catalog. It links `docs/repos/_template.md` as the Tier-1 shape.
- **`docs/adr/`** — keep `0001-record-architecture-decisions.md` (it's generic and useful).
  Write one ADR per known decision using `_template.md`. **If the code repo already records
  these decisions** (see §1.5), don't copy them verbatim into a second set that will drift —
  reference the repo's ADRs, or lift them up and leave a pointer behind.
- **`.claude/hooks/ask-before-risky-commands.sh`** — add the command families the user named
  to `RISKY_WORDS` (edit the marked line), mirrored in `permissions.ask` (see above). The
  defaults already gate cloud CLIs, `git`/`docker push`, `git clean`, recursive `rm`,
  `find -delete`, package publishing, `gh pr merge`/`repo delete`/releases, and a deploy
  script run by path; add `ssh`, a bespoke deploy CLI, etc. as needed.
  (`session-brief.sh` needs no editing — it degrades by itself on single-repo hubs.)
- **`TEAM.md`** — fill or delete, per the interview.
- **`README.md`** (the hub's own) — customize the intro, the key-repos table, and the
  "where to read next" list.

After filling a file, **remove the `<!-- TEMPLATE: … -->` guidance comments** from it.

---

## 5. Wire it up and verify

- Make the hooks and scripts executable: `chmod +x .claude/hooks/*.sh scripts/*.sh`.
- If multi-repo: `make repos` (links/clones the repos), then `make status` (branches +
  dirty state). Report what linked and what's missing — don't claim success you didn't see.
- **If the user opted into linked-repo pointers (§2.9):** add a thin `AGENTS.md` to each
  linked repo *through that repo's normal PR flow* — never commit into a linked repo behind
  the user's back. The shape:

  ```markdown
  # AGENTS.md — <repo>

  This repo is coordinated from the <project> Project Hub: <hub location / URL>.
  Before non-trivial changes, read the hub's AGENTS.md (working agreement) and
  CONTEXT.md (shared language). Invariants that bind this repo: <the 1–3 that
  apply, stated verbatim, each citing its ADR>.
  ```

  If the repo already has an `AGENTS.md`, append a short "Coordinated from the hub"
  section instead of replacing it.
- The `.github/workflows/docs-ci.yml` gate (markdownlint + offline link check) runs once the
  hub is pushed to GitHub; keep it, or delete `.github/` and `.markdownlint-cli2.jsonc` if the
  hub won't live on GitHub. If the user wants an *agentic* review lane too (tracker
  freshness, doc consistency on PRs), offer a workflow on `anthropics/claude-code-action@v1`
  — opt-in only, since it needs an API-key secret configured.
- **Run the verifier:** `scripts/verify.sh` inside the hub — it ships with the hub (this
  template repo wraps the same script as `scripts/verify-hub.sh <hub-dir>`). It fails on
  leftover placeholders / template markers, non-executable hooks, broken internal links,
  and links into `repos/` — the §7 checks, automated. Fix everything it flags before
  reporting done.
- **Finalize `.hub-meta.yml`** — confirm `template.sha` is the commit you actually
  scaffolded from and `dropped:` lists everything you removed. This file is what turns a
  future `/update-hub` run (see [`UPDATE.md`](UPDATE.md)) into a clean three-way merge
  instead of guesswork.
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
| `{{TEMPLATE_URL}}` | This template repo's clone URL | `https://github.com/acme-inc/project-hub` |
| `{{TEMPLATE_SHA}}` | Template commit the hub was generated from | `62c9ca8` |
| `{{HUB_LAYOUT}}` | `multi-repo` or `single-repo` | `multi-repo` |

Tokens live in Markdown, the scripts, `repos.manifest`, `.claude/settings.json`
(`{{CLONE_WORKSPACE}}` in `additionalDirectories`), **and `.hub-meta.yml`** (the three
template-provenance tokens) — `scripts/verify.sh` catches any you miss.

---

## 7. Quality bar (don't skip)

- **Strip every template-author example.** The generated hub must contain **zero** details
  from any other project. The verifier greps for leftover placeholder tokens, template
  markers, and broken links — run it (see §5); also eyeball for stray example strings.
- **Don't invent facts.** If you don't know a domain, an account, a status — write `TBD`
  and flag it. A confident-but-wrong hub is worse than an honest sparse one.
- **Never link into `repos/`** from hub docs — cite those paths as inline code. `repos/` is
  gitignored, so such links break docs CI and fresh clones; the verifier fails on them.
- **Respect the wordmark casing** the user gave you, everywhere user-facing.
- **Scale to the project.** A small project doesn't need 10 workstreams or 5 ADRs. Delete
  what doesn't earn its place; the skeleton is a menu, not a mandate.
- **Single-repo projects:** drop the linking machinery (§2.2), the `additionalDirectories`
  key and `make`/`repos.sh` allow-entries in `.claude/settings.json`, and the
  `onboard-repo` skill — don't ship dead tooling. Record every dropped path in
  `.hub-meta.yml` `dropped:` so template updates don't resurrect them.

When you're done, the user should be able to open the hub and have a sharp, honest cockpit
for their project — and you (or any agent) should be able to operate in it from `AGENTS.md`
+ `CONTEXT.md` alone.
