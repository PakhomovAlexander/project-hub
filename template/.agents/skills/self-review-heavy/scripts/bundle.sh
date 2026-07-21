#!/usr/bin/env bash
# bundle.sh — build a review bundle for a change: diff vs base, changed files,
# commit messages, diffstat, candidate tests. Read-only on the repo, no network.
#
# Usage:
#   bundle.sh [-C <repo-dir>] [--base <ref>] [--uncommitted] [--out <dir>]
#
#   --base         diff base ref (default: auto — first of origin/master,
#                  origin/main, master, main that exists)
#   --uncommitted  include working-tree changes (and list untracked files)
#   --out          bundle directory (default: <repo>/.git/self-review/<ts>-<branch>)
#
# Prints a short summary; the LAST line of stdout is the bundle directory.
set -euo pipefail

REPO="."
BASE=""
OUT=""
UNCOMMITTED=0

while [ $# -gt 0 ]; do
  case "$1" in
    -C) REPO="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --uncommitted) UNCOMMITTED=1; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "bundle.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$REPO"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "bundle.sh: not a git repo: $REPO" >&2; exit 2; }

if [ -z "$BASE" ]; then
  for cand in origin/master origin/main master main; do
    if git rev-parse --verify --quiet "$cand^{commit}" >/dev/null; then BASE="$cand"; break; fi
  done
fi
[ -n "$BASE" ] || { echo "bundle.sh: cannot auto-detect a base ref; pass --base" >&2; exit 2; }

MERGE_BASE="$(git merge-base "$BASE" HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
TS="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="$(git rev-parse --absolute-git-dir)/self-review/$TS-$(echo "$BRANCH" | tr '/' '_')"
mkdir -p "$OUT"

if [ "$UNCOMMITTED" -eq 1 ]; then
  git diff "$MERGE_BASE" > "$OUT/diff.patch"
  git diff --name-status "$MERGE_BASE" > "$OUT/files.txt"
  git diff --stat "$MERGE_BASE" > "$OUT/stats.txt"
  git ls-files --others --exclude-standard > "$OUT/untracked.txt"
else
  git diff "$MERGE_BASE" HEAD > "$OUT/diff.patch"
  git diff --name-status "$MERGE_BASE" HEAD > "$OUT/files.txt"
  git diff --stat "$MERGE_BASE" HEAD > "$OUT/stats.txt"
fi
git log --reverse --format='%h %s%n%b' "$MERGE_BASE..HEAD" > "$OUT/commits.txt"

# Changed test files, and candidate tests matched by name tokens of changed
# source files (camelCase split at case boundaries, snake tokens >= 5 chars).
awk '{print $NF}' "$OUT/files.txt" > "$OUT/.paths"
grep -E '(^|/)tests?/' "$OUT/.paths" > "$OUT/tests_changed.txt" || true
grep -Ev '(^|/)tests?/' "$OUT/.paths" | while IFS= read -r f; do
  b="${f##*/}"; b="${b%%.*}"
  printf '%s\n' "$b" \
    | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '\n'
done | awk 'length($0) >= 5' | sort -u | head -20 > "$OUT/.tokens"

: > "$OUT/tests_candidates.txt"
if [ -s "$OUT/.tokens" ]; then
  pat="$(paste -sd'|' - < "$OUT/.tokens")"
  git ls-files -- 'tests/*' '*/tests/*' 2>/dev/null \
    | grep -E -i "($pat)" | sort -u | head -200 > "$OUT/tests_candidates.txt" || true
fi
rm -f "$OUT/.paths" "$OUT/.tokens"

{
  echo "repo=$(basename "$(git rev-parse --show-toplevel)")"
  echo "branch=$BRANCH"
  echo "head=$(git rev-parse HEAD)"
  echo "base=$BASE"
  echo "merge_base=$MERGE_BASE"
  echo "uncommitted=$UNCOMMITTED"
  echo "created=$TS"
  echo "files_changed=$(wc -l < "$OUT/files.txt" | tr -d ' ')"
  echo "diff_lines=$(wc -l < "$OUT/diff.patch" | tr -d ' ')"
} > "$OUT/meta.env"

sed 's/^/  /' "$OUT/meta.env"
echo "$OUT"
