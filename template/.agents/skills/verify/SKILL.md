---
name: verify
description: Self-check the hub — placeholders, links, executable tooling, workflow smoke tests, provenance, tracker freshness, and doc token budgets. Run before pushing doc or hub-tooling changes and after bulk edits.
---

# Verify the hub

1. Run `scripts/verify.sh` from the hub root. It's the local form of what docs CI
   enforces on every PR, plus hub-specific checks CI can't do.
2. **Fix what's mechanical, yourself:**
   - `NOT EXECUTABLE` → `chmod +x` the file.
   - Broken relative links → repoint to where the target actually lives (find it; don't
     guess), or drop the link if the target is gone on purpose.
   - Links into `repos/` → replace with inline code (`repos/<repo>/path`) — such links
     break in CI because `repos/` is gitignored.
   - Leftover placeholder tokens or template markers → fill with the real value if you
     know it; otherwise ask, don't invent.
   - A failed `tests/smoke-*.mjs` test → reproduce it directly with `node`, then fix the
     workflow or its test. The verifier executes these only for its own hub, never for an
     external directory passed as an argument.
   - `OVER BUDGET` → move content to its cold pair (a workstream's `log.md`,
     `docs/tracker-archive.md`) **verbatim** — never fix a budget by deleting or
     summarizing away the record. `HUB_BUDGET_STRICT=1` turns the warning into a failure.
3. **Escalate what's factual:** a stale-tracker warning means the board may be lying —
   run `/tracker` (or flag it) rather than just editing the date.
4. Done = `scripts/verify.sh` exits 0. Re-run it after your fixes and say so.
