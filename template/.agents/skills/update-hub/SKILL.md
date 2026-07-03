---
name: update-hub
description: Pull the latest template improvements into this hub — fetch the template recorded in .hub-meta.yml, diff since the recorded commit, re-apply with this hub's values, verify. Use when asked to update or upgrade the hub from its template.
---

# Update the hub from its template

This hub was generated from a Project Hub template; `.hub-meta.yml` at the hub root
records which one and at what commit. The update procedure lives **in the template
repo** (its `UPDATE.md`), not here — so every hub, however old, runs the latest version
of it. This skill just gets you there:

1. Read `.hub-meta.yml` (no file? look for a `generated from project-hub@<sha>` stamp
   at the bottom of `README.md`, and ask the user for the template URL).
2. Clone `template.url` into a scratch directory — a full clone, the update diffs
   against the recorded sha.
3. Open `UPDATE.md` at the root of that clone and **follow it top to bottom**. It
   defines the three-way merge: what you may update freely (machinery), what you must
   never overwrite (this hub's own docs), and the verify + provenance-bump steps.
4. Done = the hub's `scripts/verify.sh` passes, `.hub-meta.yml` points at the new
   template sha, and your summary lists every applied / merged / skipped change.
