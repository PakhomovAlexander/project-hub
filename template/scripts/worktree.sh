#!/usr/bin/env bash
# {{PROJECT_NAME}} Project Hub — isolated workspaces for parallel agents.
#
# Run several agents over this hub at once without fs / git / branch collisions.
# A single checkout has ONE working tree, index and HEAD, so two agents that
# switch branches or stage files stomp each other. `git worktree` gives each
# agent its own directory + branch + index backed by the SAME object store
# (cheap — no re-clone), and git refuses to check out one branch in two
# worktrees, so the collision is structurally impossible.
#
# Two kinds of workspace — pick the one that matches the task:
#
#   hub  — for the hub's own docs / tooling. Placed as a SIBLING of the hub
#          (../<hub>-wt-<name>) so the relative repos/* symlinks still resolve
#          into the clone workspace.
#   repo — for editing one linked repo. A worktree of that repo's real clone.
#          Needed only when two agents touch the SAME linked repo: repos/<name>
#          is a symlink to one shared clone, so worktreeing the HUB does NOT
#          isolate it. Work in this dir directly (not via repos/<name>).
#          (Multi-repo hubs only — a single-repo hub has no repos/* to worktree.)
#
# Usage:
#   scripts/worktree.sh new  <name> [base]         # hub wt     -> ../<hub>-wt-<name>       on agent/<name> (base: main)
#   scripts/worktree.sh repo <name> <repo> [base]  # linked wt  -> <workspace>/<clone>-wt-<name> on agent/<name> (base: origin/<default>)
#   scripts/worktree.sh ls                         # list every agent worktree (hub + linked)
#   scripts/worktree.sh rm   <name>                # remove <name>'s worktrees, prune, drop the branch if merged
#
# Teardown refuses to discard uncommitted work; re-run with FORCE=1 to override.
#
# Env:
#   HUB_CLONE_ROOT  where the real clones live   (default: <hub>/{{CLONE_WORKSPACE}})

set -euo pipefail

HUB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
PARENT_DIR="$(cd -- "${HUB_DIR}/.." >/dev/null 2>&1 && pwd)"
HUB_BASE="$(basename -- "$HUB_DIR")"
# Resolve the clone workspace the same way scripts/repos.sh does, so both agree.
CLONE_ROOT="${HUB_CLONE_ROOT:-$(cd -- "${HUB_DIR}/$(dirname -- "{{CLONE_WORKSPACE}}")" >/dev/null 2>&1 && pwd)/$(basename -- "{{CLONE_WORKSPACE}}")}"
BRANCH_PREFIX="agent"

die()  { echo "worktree: error: $*" >&2; exit 1; }
note() { echo "  $*"; }

valid_name() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die "bad agent name '${1:-}' — use letters, digits, . _ - (e.g. NAME=tracker)"
}

# Remote default branch of a clone (main / master), with safe fallbacks.
default_branch() {
  local ref
  ref="$(git -C "$1" rev-parse --abbrev-ref origin/HEAD 2>/dev/null || true)"
  if [ -n "$ref" ] && [ "$ref" != "origin/HEAD" ]; then echo "${ref#origin/}"; return; fi
  git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main
}

# Resolve the real clone path behind repos/<canonical>; dies on unknown/broken.
resolve_repo() {
  local link="${HUB_DIR}/repos/$1"
  [ -L "$link" ] || die "unknown repo '$1' — see: make list"
  ( cd -- "$link" >/dev/null 2>&1 && pwd -P ) || die "repos/$1 link is broken — run: make repos"
}

# add_worktree <git_dir> <dir> <branch> <base>
add_worktree() {
  local g="$1" dir="$2" branch="$3" base="$4"
  if [ -e "$dir" ]; then
    if git -C "$g" worktree list --porcelain | awk '/^worktree /{print $2}' \
         | grep -qxF "$(cd -- "$dir" && pwd -P)"; then
      note "(already a worktree) $dir"; return 0
    fi
    die "$dir exists but is not a worktree — remove it or pick another name"
  fi
  if git -C "$g" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "$g" worktree add "$dir" "$branch" >/dev/null
    note "(attached existing branch ${branch})"
  else
    git -C "$g" worktree add --no-track -b "$branch" "$dir" "$base" >/dev/null
    note "(new branch ${branch} off ${base})"
  fi
}

# remove_worktree <git_dir> <dir>  -> 0 removed, 1 had changes (kept)
remove_worktree() {
  local g="$1" dir="$2" force=""
  [ "${FORCE:-}" = "1" ] && force="--force"
  [ -e "$dir" ] || return 0
  if git -C "$g" worktree remove $force "$dir" 2>/dev/null; then
    echo "removed $dir"; return 0
  fi
  echo "KEPT  $dir — has uncommitted work; commit/push there, or re-run with FORCE=1" >&2
  return 1
}

drop_branch() {  # <git_dir> <branch>
  local g="$1" b="$2"
  git -C "$g" show-ref --verify --quiet "refs/heads/${b}" || return 0
  if git -C "$g" branch -d "$b" >/dev/null 2>&1; then
    echo "deleted merged branch ${b} ($(basename "$g"))"
  else
    echo "kept   branch ${b} ($(basename "$g")) — unmerged; drop when sure: git -C $g branch -D ${b}" >&2
  fi
}

cmd_new() {
  valid_name "${1:-}"
  local name="$1" base="${2:-main}"
  local dir="${PARENT_DIR}/${HUB_BASE}-wt-${name}" branch="${BRANCH_PREFIX}/${name}"
  echo "hub workspace for agent '${name}':"
  add_worktree "$HUB_DIR" "$dir" "$branch" "$base"
  # repos/ is gitignored (recreated by `make repos`), so a fresh worktree lacks it.
  # Mirror the hub's symlinks — relative + sibling placement keeps them resolving.
  if [ -e "$dir/repos" ]; then
    :  # already populated (idempotent re-run)
  elif [ -d "${HUB_DIR}/repos" ] && cp -RP "${HUB_DIR}/repos" "$dir/repos" 2>/dev/null; then
    note "(mirrored repos/* symlinks into the worktree)"
  fi
  note "path:   ${dir}"
  note "branch: ${branch}"
  note "launch: cd ${dir} && claude"
  note "if another agent edits the same linked repo, give this one a private clone:"
  note "        make worktree-repo NAME=${name} REPO=<repo>"
}

cmd_repo() {
  valid_name "${1:-}"
  [ -n "${2:-}" ] || die "usage: make worktree-repo NAME=<name> REPO=<repo> [BASE=<ref>]"
  local name="$1" repo="$2"
  local real; real="$(resolve_repo "$repo")"
  local clone; clone="$(basename -- "$real")"
  local base="${3:-origin/$(default_branch "$real")}"
  local dir="${CLONE_ROOT}/${clone}-wt-${name}" branch="${BRANCH_PREFIX}/${name}"
  echo "linked-repo workspace for agent '${name}' on ${repo} (${clone}):"
  add_worktree "$real" "$dir" "$branch" "$base"
  note "path:   ${dir}"
  note "branch: ${branch}"
  note "commit: inside that dir, against {{ORG}}/${clone}"
  note "!! this agent edits ${repo} HERE — NOT via repos/${repo} (that's the shared clone)"
}

cmd_ls() {
  echo "# hub worktrees"
  git -C "$HUB_DIR" worktree list
  local link real extra
  for link in "${HUB_DIR}"/repos/*; do
    [ -L "$link" ] || continue
    real="$( cd -- "$link" >/dev/null 2>&1 && pwd -P )" || continue
    extra="$(git -C "$real" worktree list 2>/dev/null | tail -n +2)"
    [ -n "$extra" ] || continue
    echo
    echo "# $(basename "$link") ($(basename "$real"))"
    git -C "$real" worktree list
  done
}

cmd_rm() {
  valid_name "${1:-}"
  local name="$1"
  local branch="${BRANCH_PREFIX}/${name}"
  local rc=0

  if ! remove_worktree "$HUB_DIR" "${PARENT_DIR}/${HUB_BASE}-wt-${name}"; then rc=1; fi
  git -C "$HUB_DIR" worktree prune
  [ "$rc" -eq 0 ] && drop_branch "$HUB_DIR" "$branch"

  local link real clone pdir
  for link in "${HUB_DIR}"/repos/*; do
    [ -L "$link" ] || continue
    real="$( cd -- "$link" >/dev/null 2>&1 && pwd -P )" || continue
    clone="$(basename -- "$real")"
    pdir="${CLONE_ROOT}/${clone}-wt-${name}"
    [ -e "$pdir" ] || continue
    if remove_worktree "$real" "$pdir"; then
      git -C "$real" worktree prune
      drop_branch "$real" "$branch"
    else
      rc=1
    fi
  done

  [ "$rc" -eq 0 ] && echo "agent '${name}' workspaces cleaned up"
  return "$rc"
}

case "${1:-}" in
  new)  shift; cmd_new  "$@" ;;
  repo) shift; cmd_repo "$@" ;;
  ls)   cmd_ls ;;
  rm)   shift; cmd_rm   "$@" ;;
  ""|-h|--help|help)
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command '$1' (new | repo | ls | rm)" ;;
esac
