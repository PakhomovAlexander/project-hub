---
name: resume
description: Pick up an in-flight workstream cold — load its design doc, verify its claimed state against reality, and continue from the "resume here" list. Use when returning to interrupted work or taking over someone else's stream.
argument-hint: [workstream]
---

# Resume a workstream

1. **Pick the stream.** No argument given → list `docs/workstreams/*.md` with each doc's
   `Status:` line and ask which one (or pick the only in-progress one).
2. **Load the context, in order:**
   - The workstream doc itself — especially **Status**, **Acceptance criteria**, and
     **Open work (resume here)**, which is the live to-do.
   - Its rows in `docs/tracker.md`, and any ADRs the doc links.
3. **Verify before trusting.** Status lines drift. Check the doc's claims against
   reality: do the branches/PRs it mentions exist and in what state (`gh pr view`), did
   the files it says exist land, is CI green? Note every divergence found.
4. **Report the resume point:** where the stream actually stands, what changed since the
   doc was last updated, and the next 1–3 concrete steps from **Open work**.
5. **Fix the doc first.** If the doc had drifted, update its Status header and Open work
   list *before* starting new work — the next person resumes from what you leave behind.
