#!/usr/bin/env bash
# checks.sh — run a list of named checks and record a machine-readable summary.
#
# Usage:
#   checks.sh --file <checks.tsv> --out <bundle-dir> [-C <dir>] [--halt]
#             [--subst <name>=<file>]...
#
#   <checks.tsv>  one check per line:  <name><TAB><shell command>
#                 Blank lines and lines starting with '#' are skipped.
#   -C            directory to run the commands in (default: .)
#   --halt        stop at the first failing check
#   --subst       fill a @@name@@ placeholder in every command from a file of
#                 values, ONE PER LINE, each shell-quoted here and joined with
#                 spaces. Repeatable. Always render selectors this way rather
#                 than pasting them into the TSV yourself: values derived from
#                 the diff (test paths from the bundle) are attacker-controlled
#                 when the change under review is not yours, and commands run
#                 through `bash -c` — an unquoted `tests/x; curl … | sh #.py`
#                 is arbitrary code execution. Quoting here is mechanical and
#                 cannot be forgotten. A @@placeholder@@ left unfilled means the
#                 check is NOT RUN and is recorded fail — it verified nothing.
#
# Writes <out>/checks/<name>.log per check and (re)writes <out>/checks.tsv —
# truncated at start, so it always reflects only the latest run:
#   <name><TAB>pass|fail<TAB><seconds><TAB><log-file>
# Exit: 0 if at least one check ran and every executed check passed;
#       1 on any failure OR a vacuous run (zero checks executed).
set -uo pipefail

FILE=""
OUT=""
DIR="."
HALT=0
# Parallel arrays, not an associative one: this has to run on macOS stock
# bash 3.2 like every other script the template ships.
SUBST_NAMES=()
SUBST_VALS=()
SUBST_EMPTY=""

# POSIX single-quote wrapping: every embedded ' becomes '\''. Whatever the
# value contains — semicolons, backticks, $(), newlines — `bash -c` sees one
# literal word.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -C) DIR="$2"; shift 2 ;;
    --halt) HALT=1; shift ;;
    --subst)
      case "${2:-}" in
        *=*) ;;
        *) echo "checks.sh: --subst needs <name>=<file>, got: '${2:-}'" >&2; exit 2 ;;
      esac
      sname="${2%%=*}"; sfile="${2#*=}"
      [ -f "$sfile" ] || { echo "checks.sh: --subst $sname: file not found: $sfile" >&2; exit 2; }
      sval=""
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        if [ -z "$sval" ]; then sval="$(shq "$line")"; else sval="$sval $(shq "$line")"; fi
      done < "$sfile"
      # An empty value list silently changes what the command means — a test
      # runner given no selectors may run everything, or nothing, and either
      # way the check did not test the change. Say so; the gate's honesty rule
      # turns "selector resolves to nothing" into a not-verified finding.
      if [ -z "$sval" ]; then
        echo "checks.sh: --subst $sname: $sfile has no values — any check using @@${sname}@@ cannot verify anything and will be recorded fail" >&2
        SUBST_EMPTY="$SUBST_EMPTY $sname"
      fi
      SUBST_NAMES+=("$sname"); SUBST_VALS+=("$sval")
      shift 2
      ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) echo "checks.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then echo "checks.sh: --file is required and must exist" >&2; exit 2; fi
[ -n "$OUT" ] || { echo "checks.sh: --out is required" >&2; exit 2; }
mkdir -p "$OUT/checks"
if [ "$FILE" -ef "$OUT/checks.tsv" ]; then
  echo "checks.sh: --file must not be <out>/checks.tsv — the results file would truncate the input; name the list differently (e.g. checks.render.tsv)" >&2
  exit 2
fi
: > "$OUT/checks.tsv"

TAB="$(printf '\t')"
total=0
passed=0
rc=0

# `|| [ -n "$name" ]` keeps the final line alive when the TSV lacks a
# trailing newline — read returns nonzero there despite filling the fields.
while IFS="$TAB" read -r name cmd || [ -n "$name" ]; do
  [ -n "$name" ] || continue
  case "$name" in '#'*) continue ;; esac
  if [ -z "${cmd:-}" ]; then
    echo "checks.sh: line for '$name' has no command (fields must be TAB-separated)" >&2
    rc=1
    continue
  fi
  # A selector list that resolved to nothing means this check cannot test the
  # change — running it anyway (a test runner with no selectors runs
  # everything, or nothing) records a pass that answers a different question.
  unverifiable=""
  for en in $SUBST_EMPTY; do
    case "$cmd" in *"@@${en}@@"*) unverifiable="$unverifiable @@${en}@@" ;; esac
  done

  i=0
  while [ "$i" -lt "${#SUBST_NAMES[@]}" ]; do
    sn="${SUBST_NAMES[$i]}"; sv="${SUBST_VALS[$i]}"
    cmd="${cmd//@@$sn@@/$sv}"
    i=$((i + 1))
  done
  # An unfilled @@placeholder@@ means the check ran against literal text and
  # proves nothing. DOUBLE braces, because single ones are ambiguous with the
  # shell and its guests: `awk 'BEGIN {print}'` and `jq '. | {name}'` are
  # ordinary commands, and a detector that flags them blocks a legitimate gate
  # check. Nothing in sh/awk/jq emits @@name@@.
  left="$(printf '%s' "$cmd" \
    | grep -oE '@@[a-z_][a-z0-9_]*@@' | sort -u | tr '\n' ' ' || true)"
  [ -z "$left" ] || unverifiable="$unverifiable ${left% }"

  # Record it as a FAILURE rather than running it. stderr prose only becomes a
  # not-verified finding if the reading model notices and obeys it; checks.tsv
  # is the machine-readable evidence everything downstream keys on, and it must
  # not say pass for a check that never tested the change.
  if [ -n "$unverifiable" ]; then
    total=$((total + 1)); rc=1
    log="$OUT/checks/$(printf '%s' "$name" | tr -cs 'A-Za-z0-9._-' '_').log"
    echo "not run: unresolved placeholder(s):${unverifiable} — nothing was verified" > "$log"
    printf '%s\t%s\t%s\t%s\n' "$name" "fail" "0" "$log" >> "$OUT/checks.tsv"
    printf '  ✗ %s (not run — unresolved:%s)\n' "$name" "$unverifiable"
    [ "$HALT" -eq 1 ] && break
    continue
  fi

  total=$((total + 1))
  # printf, not echo: echo's trailing newline is outside the keep-set and
  # became a trailing '_' on every log name.
  log="$OUT/checks/$(printf '%s' "$name" | tr -cs 'A-Za-z0-9._-' '_').log"
  start="$(date +%s)"
  # pipefail in the CHILD shell. Without it a pipeline's status is its last
  # command's, so the `<build or test> 2>&1 | tail -N` idiom this skill's own
  # example profile teaches records `pass` no matter what the left side exits
  # — a red test suite converges green. A check that legitimately ends in an
  # early-exit consumer (`| head`, `| grep -q`) will now fail loudly on
  # SIGPIPE; that is the safe direction for a gate, and `|| true` opts out
  # per check.
  if (cd "$DIR" && bash -c "set -o pipefail; $cmd") > "$log" 2>&1; then
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
if [ "$total" -eq 0 ]; then
  echo "checks.sh: no checks executed — empty or comment-only TSV; a vacuous run is not a pass" >&2
  exit 1
fi
exit "$rc"
