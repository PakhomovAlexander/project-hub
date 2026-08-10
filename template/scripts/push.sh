#!/usr/bin/env bash
# Push the current branch after checking whether the new commit would orphan CI.
#
# Usage:
#   scripts/push.sh [-C DIR] [--repo OWNER/NAME] [--force-with-lease]
#                   [--yes] [--dry-run]
#
# The repository is inferred from a GitHub origin when --repo is omitted. The
# script refuses the default branch and detached HEAD. If queued or in-progress
# runs exist on the branch, it shows them and asks before cancelling. --yes skips
# that inner prompt; the hub's command guard still treats this wrapper as a push.

set -euo pipefail

DIR="."
REPO=""
FORCE=0
ASSUME_YES=0
DRY_RUN=0

die() { echo "push: error: $*" >&2; exit 2; }
git_c() { command git -C "$DIR" "$@"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    -C) DIR="${2:?-C needs a directory}"; shift 2 ;;
    --repo) REPO="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --force-with-lease) FORCE=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,12s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) die "unknown option '$1'" ;;
  esac
done

command -v gh >/dev/null 2>&1 || die "gh is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

branch="$(git_c symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -n "$branch" ] || die "detached HEAD or not a git repository: $DIR"

if [ -z "$REPO" ]; then
  origin="$(git_c config --get remote.origin.url 2>/dev/null || true)"
  case "$origin" in
    git@github.com:*) REPO="${origin#git@github.com:}" ;;
    ssh://git@github.com/*) REPO="${origin#ssh://git@github.com/}" ;;
    https://github.com/*) REPO="${origin#https://github.com/}" ;;
    http://github.com/*) REPO="${origin#http://github.com/}" ;;
    *) die "origin is not a GitHub repository; pass --repo OWNER/NAME" ;;
  esac
  REPO="${REPO%.git}"
fi
[[ "$REPO" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] \
  || die "invalid GitHub repository '$REPO' (expected OWNER/NAME)"

if ! default_branch="$(gh repo view "$REPO" --json defaultBranchRef \
    --jq '.defaultBranchRef.name')"; then
  die "could not resolve the GitHub default branch; refusing to push"
fi
[[ "$default_branch" =~ ^[^[:space:]]+$ ]] \
  || die "GitHub returned an invalid default branch; refusing to push"
if [ "$branch" = "$default_branch" ]; then
  die "refusing to push default branch '$branch' — use a feature branch and PR"
fi

local_sha="$(git_c rev-parse HEAD)"
if ! remote_ref="$(git_c ls-remote --heads origin "refs/heads/$branch")"; then
  die "could not inspect the remote branch; refusing to cancel CI or push"
fi
remote_sha=""
if [ -n "$remote_ref" ]; then
  case "$remote_ref" in
    *$'\n'*) die "remote branch lookup returned multiple refs; refusing to push" ;;
  esac
  IFS=$'\t' read -r remote_sha remote_name remote_extra <<< "$remote_ref"
  if ! [[ "$remote_sha" =~ ^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$ ]] \
    || [ "$remote_name" != "refs/heads/$branch" ] || [ -n "$remote_extra" ]; then
    die "remote branch lookup returned malformed data; refusing to push"
  fi
fi

if [ -n "$remote_sha" ] && [ "$local_sha" = "$remote_sha" ]; then
  echo "repo=$REPO branch=$branch already matches origin/$branch"
  echo "no push or CI cancellation needed"
  exit 0
fi

ahead="$(git_c rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo '?')"
echo "repo=$REPO branch=$branch unpushed=$ahead force=$FORCE"

preflight_args=(push --dry-run)
push_args=(push)
upstream="$(git_c rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [ "$FORCE" -eq 1 ]; then
  tracked_sha="$(git_c rev-parse "refs/remotes/origin/$branch" 2>/dev/null || true)"
  if [ -n "$tracked_sha" ]; then
    lease="--force-with-lease=refs/heads/$branch:$tracked_sha"
    preflight_args+=("$lease")
    push_args+=("$lease")
  fi
fi
preflight_args+=(origin "HEAD:refs/heads/$branch")

# Prove the ref update is currently acceptable before discarding any live CI.
# The real push can still lose a race, but force pushes retain their exact lease.
if ! preflight="$(git_c "${preflight_args[@]}" 2>&1)"; then
  printf '%s\n' "$preflight" >&2
  die "push preflight failed; no CI runs were cancelled"
fi

if ! live_json="$(gh run list --repo "$REPO" --branch "$branch" --limit 100 \
    --json databaseId,status,headSha,workflowName)"; then
  die "could not inspect branch CI; refusing to push without that check"
fi
if ! printf '%s' "$live_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
  die "GitHub returned malformed branch CI data; refusing to push"
fi
live="$(printf '%s' "$live_json" | jq -r --arg observed "$remote_sha" '
  .[] | select(
    (.status == "in_progress" or .status == "queued")
    and .headSha == $observed
  ) | (.workflowName | tostring | gsub("[\\t\\r\\n]"; " ")) as $workflow
  | "\(.databaseId)\t\(.status)\t\($workflow)\t\(.headSha[0:12])"')"

if [ -n "$live" ]; then
  echo
  echo "Queued or in-progress runs this push would orphan:"
  printf '%s\n' "$live" | sed 's/^/  /'
  echo
  echo "Cancelling discards the evidence those runs have gathered for their SHA."
  if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Cancel these runs and push? [y/N] " reply || reply=""
    case "$reply" in y|Y|yes|YES) : ;; *) echo "aborted"; exit 1 ;; esac
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    cancel_failed=0
    while IFS=$'\t' read -r run_id _rest; do
      [ -n "$run_id" ] || continue
      if ! gh run cancel "$run_id" --repo "$REPO"; then
        cancel_failed=1
      fi
    done <<< "$live"
    [ "$cancel_failed" -eq 0 ] \
      || die "one or more runs could not be cancelled; push was not attempted"
  fi
else
  echo "no queued or in-progress runs for the observed remote commit"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run: push not attempted"
  exit 0
fi

[ -n "$upstream" ] || push_args+=(-u)
push_args+=(origin "HEAD:refs/heads/$branch")
git_c "${push_args[@]}"
