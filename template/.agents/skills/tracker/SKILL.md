---
name: tracker
description: Refresh docs/tracker.md — the live status board — so it is true right now. Use at the start or end of a work session, when the session brief flags the snapshot as stale, or after anything lands.
---

# Refresh the tracker

The tracker is only useful if it's current, and only trustworthy if it's honest.

1. **Gather reality first, then edit.**
   - `make status` (multi-repo hubs) — branch + dirty state per linked repo.
   - The backlog, wherever `AGENTS.md` says it lives (e.g. `gh issue list` /
     `gh pr list --state all` per repo for GitHub-based projects).
   - Anything the user said this session about what moved.
2. **Update `docs/tracker.md`:**
   - The `Snapshot:` line — today's date + a one-line "what's true right now".
   - The reality-vs-plan blockquote — if reality has diverged from `docs/plan.md`, say so
     plainly here; don't silently rewrite the plan.
   - **In flight now** — one row per active item: state, where (link the PR/workstream),
     and the *next concrete action*.
   - **Open decisions / gaps** — mark resolved ones ☑ and strike them; the history of what
     was decided should stay readable.
   - Workstream states, and the repo branch snapshot table (multi-repo hubs).
3. **Rules:**
   - Don't invent status. Unknown = `TBD`; blocked-on-a-human = ⚠. A confident-but-wrong
     board is worse than an honest sparse one.
   - Merge ≠ done — respect the issue lifecycle in `docs/issue-lifecycle.md`.
   - Keep the diff minimal and factual; no cosmetic rewording.
   - Archive, don't delete: when a dated point-in-time section (an old repo-branch
     snapshot, a superseded status block) stops being current, move it to
     `docs/tracker-archive.md` (create it on first use). The board stays short enough
     to read — and to inject into the session brief — while history stays greppable.
