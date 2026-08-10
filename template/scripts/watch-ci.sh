#!/usr/bin/env bash
# Watch one pull request until all GitHub checks are terminal.
#
# Usage:
#   scripts/watch-ci.sh <pr-number-or-url> [-C DIR] [--repo OWNER/NAME]
#                       [--interval SECONDS] [--gates REGEX]
#                       [--max-errors N]
#
# Every failure and cancellation is reported. Successful checks are reported only
# when their name matches --gates (or HUB_CI_GATES). Exit 0 means all checks passed;
# exit 1 means at least one failed or was cancelled; exit 2 is a tooling/API error.

set -euo pipefail

DIR="."
REPO=""
PR=""
INTERVAL=60
GATES="${HUB_CI_GATES:-}"
MAX_ERRORS=3

die() { echo "watch-ci: error: $*" >&2; exit 2; }
git_c() { command git -C "$DIR" "$@"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    -C) DIR="${2:?-C needs a directory}"; shift 2 ;;
    --repo) REPO="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --interval) INTERVAL="${2:?--interval needs seconds}"; shift 2 ;;
    --gates) GATES="${2:?--gates needs a regex}"; shift 2 ;;
    --max-errors) MAX_ERRORS="${2:?--max-errors needs a count}"; shift 2 ;;
    -h|--help)
      sed -n '2,13s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) die "unknown option '$1'" ;;
    *) [ -z "$PR" ] || die "only one pull request may be watched"; PR="$1"; shift ;;
  esac
done

[ -n "$PR" ] || die "a pull request number or URL is required"
[[ "$INTERVAL" =~ ^[0-9]+$ ]] || die "--interval must be a non-negative integer"
[[ "$MAX_ERRORS" =~ ^[1-9][0-9]*$ ]] || die "--max-errors must be a positive integer"
command -v gh >/dev/null 2>&1 || die "gh is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

if [[ "$PR" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(/.*)?$ ]]; then
  [ -n "$REPO" ] || REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  PR="${BASH_REMATCH[3]}"
fi

if [ -z "$REPO" ]; then
  origin="$(git_c remote get-url origin 2>/dev/null || true)"
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

if [ -n "$GATES" ] && ! jq -n -e --arg pattern "$GATES" \
    'try ("" | test($pattern) | true) catch false' >/dev/null 2>&1; then
  die "--gates is not a valid regular expression"
fi

previous=""
first=1
errors=0

while true; do
  if ! checks="$(gh pr checks "$PR" --repo "$REPO" --json name,bucket 2>&1)"; then
    errors=$((errors + 1))
    echo "watch-ci: GitHub query failed ($errors/$MAX_ERRORS): $checks" >&2
    [ "$errors" -lt "$MAX_ERRORS" ] || die "GitHub query failed repeatedly"
    sleep "$INTERVAL"
    continue
  fi
  if ! printf '%s' "$checks" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    errors=$((errors + 1))
    echo "watch-ci: no checks found yet ($errors/$MAX_ERRORS)" >&2
    [ "$errors" -lt "$MAX_ERRORS" ] || die "no checks appeared"
    sleep "$INTERVAL"
    continue
  fi
  errors=0

  current="$(printf '%s' "$checks" | jq -r --arg gates "$GATES" '
    .[] | select(
      .bucket == "fail" or .bucket == "cancel"
      or ($gates != "" and .bucket == "pass" and (.name | test($gates)))
    ) | "\(.name): \(.bucket)"' | sort)"

  if [ "$first" -eq 1 ]; then
    printf '%s' "$checks" | jq -r '
      ([.[] | select(.bucket == "pass")] | length) as $pass
      | ([.[] | select(.bucket == "fail")] | length) as $fail
      | ([.[] | select(.bucket == "cancel")] | length) as $cancel
      | ([.[] | select(.bucket == "pending")] | length) as $pending
      | "watching PR: \($pass) pass, \($fail) fail, "
        + "\($cancel) cancelled, \($pending) pending at attach"'
    [ -z "$current" ] || printf '%s\n' "$current"
    first=0
  else
    comm -13 <(printf '%s\n' "$previous") <(printf '%s\n' "$current") \
      | awk 'NF'
  fi
  previous="$current"

  pending="$(printf '%s' "$checks" | jq '[.[] | select(.bucket == "pending")] | length')"
  if [ "$pending" -eq 0 ]; then
    failed="$(printf '%s' "$checks" | jq '[.[] | select(.bucket == "fail")] | length')"
    cancelled="$(printf '%s' "$checks" | jq '[.[] | select(.bucket == "cancel")] | length')"
    echo "all checks terminal — $failed failed, $cancelled cancelled"
    [ "$failed" -eq 0 ] && [ "$cancelled" -eq 0 ] && exit 0
    exit 1
  fi
  sleep "$INTERVAL"
done
