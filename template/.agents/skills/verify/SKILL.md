---
name: verify
description: Self-check the hub — leftover placeholders, broken internal links, links into gitignored repos/, non-executable hooks, stale tracker. Run before pushing doc changes or after any bulk edit.
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
3. **Escalate what's factual:** a stale-tracker warning means the board may be lying —
   run `/tracker` (or flag it) rather than just editing the date.
4. Done = `scripts/verify.sh` exits 0. Re-run it after your fixes and say so.
