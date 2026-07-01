# {{PROJECT_NAME}} Project Hub — top-level tooling.
#
#   make repos        — link the key repos into ./repos (clone what's missing)
#   make repos-check  — fail if any repo is missing or a link is broken (CI)
#   make status       — branch + dirty state across every key repo
#   make list         — print the repo manifest
#
#   make worktree NAME=x             — isolated hub workspace for a parallel agent
#   make worktree-repo NAME=x REPO=y — private worktree of one linked repo (shared-repo case)
#   make worktree-ls                 — list every agent worktree (hub + linked)
#   make worktree-rm NAME=x          — tear an agent's workspaces down
#
# TEMPLATE: for a single-repo project, delete the `repos*`/`status`/`list` targets along
# with scripts/repos.sh and repos.manifest, and drop the `worktree-repo` target (keep the
# other `worktree*` targets — parallel agents on the hub's own docs still collide).

.PHONY: help repos repos-check status list \
	worktree worktree-repo worktree-ls worktree-rm

help:
	@echo "Targets:"
	@echo "  make repos        — link the key repos into ./repos (clone what's missing)"
	@echo "  make repos-check  — fail if a repo is missing / a link is broken (CI)"
	@echo "  make status       — branch + dirty state across every key repo"
	@echo "  make list         — print the repo manifest"
	@echo "  make worktree NAME=x             — isolated hub workspace for a parallel agent"
	@echo "  make worktree-repo NAME=x REPO=y — private worktree of one linked repo"
	@echo "  make worktree-ls                 — list every agent worktree (hub + linked)"
	@echo "  make worktree-rm NAME=x          — tear an agent's workspaces down"

repos:
	scripts/repos.sh

repos-check:
	scripts/repos.sh --check

status:
	scripts/repos.sh --status

list:
	scripts/repos.sh --list

# Parallel-agent worktrees — see docs/parallel-agents.md
worktree:
	@scripts/worktree.sh new "$(NAME)" $(BASE)

worktree-repo:
	@scripts/worktree.sh repo "$(NAME)" "$(REPO)" $(BASE)

worktree-ls:
	@scripts/worktree.sh ls

worktree-rm:
	@scripts/worktree.sh rm "$(NAME)"
