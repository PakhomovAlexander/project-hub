---
name: onboard-repo
description: Link a new repo into the hub and document it — manifest entry, symlink, Tier-1 reference doc with the dev loop, catalog row. Use when the project grows a repo or an existing repo isn't wired in yet.
argument-hint: <repo> [kind]
---

# Onboard a repo into the hub

1. **Manifest.** Add a line to `repos.manifest`:
   `canonical:clone_dir:github_repo:kind` (kind: `service` | `infra` | `web` | `lib` | …).
2. **Link it.** `make repos` (clones if missing, then symlinks into `repos/<name>`), then
   `make status` and confirm the repo shows up with a branch. Report what actually
   happened — don't claim a link you didn't see.
3. **Write the Tier-1 reference:** copy `docs/repos/_template.md` to
   `docs/repos/<name>.md` and fill it *from the repo's own source* (README, CI config,
   Makefile/package scripts):
   - The **Dev loop** first — how to build, test, lint, and run. This is the single most
     valuable section for any agent that will touch the repo.
   - Role, deploy target, and which hub invariants apply (link the ADR).
   - Mark every fact **confirmed** (read from source, dated) or **inferred**. Cite paths
     as inline code, not links — `repos/` is gitignored, so links into it break docs CI.
4. **Catalog + front door.** Add a row to `docs/service-catalog.md` (status ☐, pick a
   priority) if the hub has one, and to the key-repos table in `README.md`.
5. **Verify.** `scripts/verify.sh` — links and placeholders must come back clean.
