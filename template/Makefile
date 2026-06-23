# {{PROJECT_NAME}} Project Hub — top-level tooling.
#
#   make repos        — link the key repos into ./repos (clone what's missing)
#   make repos-check  — fail if any repo is missing or a link is broken (CI)
#   make status       — branch + dirty state across every key repo
#   make list         — print the repo manifest
#
# TEMPLATE: for a single-repo project, delete this file along with scripts/repos.sh
# and repos.manifest.

.PHONY: help repos repos-check status list

help:
	@echo "Targets:"
	@echo "  make repos        — link the key repos into ./repos (clone what's missing)"
	@echo "  make repos-check  — fail if a repo is missing / a link is broken (CI)"
	@echo "  make status       — branch + dirty state across every key repo"
	@echo "  make list         — print the repo manifest"

repos:
	scripts/repos.sh

repos-check:
	scripts/repos.sh --check

status:
	scripts/repos.sh --status

list:
	scripts/repos.sh --list
