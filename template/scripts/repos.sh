#!/usr/bin/env bash
# {{PROJECT_NAME}} Project Hub — wire the key repos into ./repos as symlinks.
#
# The real clones live in a sibling workspace, each on its own branch / dirty state —
# this script never touches their contents. It links ./repos/<name> -> <workspace>/<dir>,
# and clones any repo that isn't checked out yet into that workspace first.
#
# The repo list lives in ./repos.manifest (data, not code) — edit that to add/remove repos.
#
# Usage:
#   scripts/repos.sh            # link everything (clone what's missing)
#   scripts/repos.sh --check    # exit 1 if any repo is missing / a link is broken (CI)
#   scripts/repos.sh --status   # branch + dirty state for each repo
#   scripts/repos.sh --list     # print the manifest and exit
#
# Env:
#   HUB_ORG               GitHub org for clones      (default: {{ORG}})
#   HUB_CLONE_ROOT        where the real clones live (default: <hub>/{{CLONE_WORKSPACE}})
#   HUB_MANIFEST          manifest file              (default: <hub>/repos.manifest)
#   HUB_CLONE_URL_PREFIX  URL style when gh is absent (default: git@github.com:)

set -euo pipefail

HUB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
ORG="${HUB_ORG:-{{ORG}}}"
CLONE_ROOT="${HUB_CLONE_ROOT:-$(cd -- "${HUB_DIR}/$(dirname -- "{{CLONE_WORKSPACE}}")" >/dev/null 2>&1 && pwd)/$(basename -- "{{CLONE_WORKSPACE}}")}"
CLONE_BASENAME="$(basename -- "${CLONE_ROOT}")"
MANIFEST="${HUB_MANIFEST:-${HUB_DIR}/repos.manifest}"

if [ ! -f "$MANIFEST" ]; then
  echo "manifest not found: $MANIFEST" >&2
  exit 2
fi

# Read the manifest into REPOS[], skipping comments and blank lines.
declare -a REPOS=()
while IFS= read -r line; do
  line="${line%%#*}"                       # strip inline comments
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [ -n "$line" ] && REPOS+=("$line")
done < "$MANIFEST"

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "no repos in manifest: $MANIFEST" >&2
  exit 2
fi

mode="link"
case "${1:-}" in
  --check)  mode="check"  ;;
  --status) mode="status" ;;
  --list)   mode="list"   ;;
  "")       ;;
  *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

if [ "$mode" = "list" ]; then
  printf "%-20s %-20s %-10s\n" "CANONICAL" "CLONE DIR" "KIND"
  for e in "${REPOS[@]}"; do IFS=: read -r c d _ k <<<"$e"; printf "%-20s %-20s %-10s\n" "$c" "$CLONE_BASENAME/$d" "$k"; done
  exit 0
fi

mkdir -p "${HUB_DIR}/repos"
missing=() broken=()

for e in "${REPOS[@]}"; do
  IFS=: read -r canonical clone_dir repo kind <<<"$e"
  src="${CLONE_ROOT}/${clone_dir}"
  link="${HUB_DIR}/repos/${canonical}"

  if [ "$mode" = "status" ]; then
    if [ -d "${src}/.git" ]; then
      br="$(git -C "$src" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      dirty="$(git -C "$src" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      printf "%-20s %-32s dirty=%-4s %s\n" "$canonical" "$br" "$dirty" "$kind"
    else
      printf "%-20s %-32s %s\n" "$canonical" "(not cloned)" "$kind"
    fi
    continue
  fi

  if [ "$mode" = "check" ]; then
    [ -d "${src}/.git" ] || missing+=("$canonical -> ${CLONE_BASENAME}/${clone_dir}")
    { [ -L "$link" ] && [ -e "$link" ]; } || broken+=("$canonical")
    continue
  fi

  # mode = link
  if [ ! -d "${src}/.git" ]; then
    echo "cloning ${ORG}/${repo} -> ${src}"
    # gh uses whatever GitHub auth you already have (HTTPS or SSH); plain git falls
    # back to SSH. Override the bare-git URL style with HUB_CLONE_URL_PREFIX
    # (e.g. "https://github.com/").
    if command -v gh >/dev/null 2>&1; then
      cloner=(gh repo clone "${ORG}/${repo}" "$src" -- --quiet)
    else
      cloner=(git clone --quiet "${HUB_CLONE_URL_PREFIX:-git@github.com:}${ORG}/${repo}.git" "$src")
    fi
    if ! "${cloner[@]}"; then
      echo "  WARN: clone failed for ${ORG}/${repo}; skipping link" >&2
      continue
    fi
  fi
  # relative symlink so the hub stays portable
  rel="$(cd -- "$HUB_DIR" && python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$src" "${HUB_DIR}/repos" 2>/dev/null || echo "$src")"
  ln -sfn "$rel" "$link"
  echo "linked repos/${canonical} -> ${rel}"
done

if [ "$mode" = "check" ]; then
  rc=0
  [ "${#missing[@]}" -gt 0 ] && { echo "missing clones: ${missing[*]}" >&2; rc=1; }
  [ "${#broken[@]}"  -gt 0 ] && { echo "broken links:  ${broken[*]}" >&2;  rc=1; }
  [ "$rc" -eq 0 ] && echo "all ${#REPOS[@]} repos present and linked"
  exit "$rc"
fi
