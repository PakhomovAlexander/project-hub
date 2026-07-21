#!/usr/bin/env bash
# checks.sh — run a list of named checks and record a machine-readable summary.
#
# Usage:
#   checks.sh --file <checks.tsv> --out <bundle-dir> [-C <dir>] [--halt]
#
#   <checks.tsv>  one check per line:  <name><TAB><shell command>
#                 Blank lines and lines starting with '#' are skipped.
#   -C            directory to run the commands in (default: .)
#   --halt        stop at the first failing check
#
# Writes <out>/checks/<name>.log per check and appends to <out>/checks.tsv:
#   <name><TAB>pass|fail<TAB><seconds><TAB><log-file>
# Exit: 0 if every executed check passed, 1 otherwise.
set -uo pipefail

FILE=""
OUT=""
DIR="."
HALT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -C) DIR="$2"; shift 2 ;;
    --halt) HALT=1; shift ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "checks.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then echo "checks.sh: --file is required and must exist" >&2; exit 2; fi
[ -n "$OUT" ] || { echo "checks.sh: --out is required" >&2; exit 2; }
mkdir -p "$OUT/checks"

TAB="$(printf '\t')"
total=0
passed=0
rc=0

while IFS="$TAB" read -r name cmd; do
  [ -n "$name" ] || continue
  case "$name" in '#'*) continue ;; esac
  if [ -z "${cmd:-}" ]; then
    echo "checks.sh: line for '$name' has no command (fields must be TAB-separated)" >&2
    rc=1
    continue
  fi
  total=$((total + 1))
  log="$OUT/checks/$(echo "$name" | tr -cs 'A-Za-z0-9._-' '_').log"
  start="$(date +%s)"
  if (cd "$DIR" && bash -c "$cmd") > "$log" 2>&1; then
    st="pass"; passed=$((passed + 1))
  else
    st="fail"; rc=1
  fi
  secs=$(( $(date +%s) - start ))
  printf '%s\t%s\t%s\t%s\n' "$name" "$st" "$secs" "$log" >> "$OUT/checks.tsv"
  if [ "$st" = pass ]; then
    printf '  ✓ %s (%ss)\n' "$name" "$secs"
  else
    printf '  ✗ %s (%ss) → %s\n' "$name" "$secs" "$log"
    tail -5 "$log" | sed 's/^/      /'
    [ "$HALT" -eq 1 ] && break
  fi
done < "$FILE"

echo "checks: $passed/$total passed"
exit "$rc"
