#!/usr/bin/env bash
# ledger.sh — findings ledger for iterative review: dedup across rounds,
# status tracking, convergence check. Storage: <dir>/ledger.jsonl + <dir>/round.
#
# Usage:
#   ledger.sh init      <dir>
#   ledger.sh bump      <dir>                          # round += 1, prints it
#   ledger.sh round     <dir>                          # print current round
#   ledger.sh add       <dir> --source <stage> <findings.json>
#   ledger.sh list      <dir> [--status open]          # JSONL to stdout
#   ledger.sh resolve   <dir> <fp> <fixed|rejected|wontfix|contested> [--note <text>]
#   ledger.sh converged <dir> [--clean-rounds 1] [--max-rounds 3] [--gate major]
#   ledger.sh report    <dir>                          # markdown summary
#
# add     appends findings not already fingerprinted (fp = hash of file+title);
#         duplicates bump last_seen_round — except a duplicate of an entry
#         resolved (fixed/rejected/wontfix) in an EARLIER round, which is
#         REOPENED: a re-report after a fix means the fix didn't hold.
#         Prints "new=N dup=M reopened=R open=K" (reopened fps listed above).
# converged exit codes: 0 converged · 1 not yet · 3 max-rounds exhausted.
#         Only entries at/above --gate severity count as blocking or as
#         convergence-resetting news; sub-gate findings never force a round.
set -euo pipefail

die() { echo "ledger.sh: $*" >&2; exit 2; }
need_jq() { command -v jq >/dev/null || die "jq is required"; }

# fp = exact file path + normalized title (case/punctuation-insensitive so
# reworded re-reports still match). The path is NOT normalized: src/foo-bar
# and src/foo_bar are different files and must not share a fingerprint.
fingerprint() {
  { printf '%s|' "$1"; printf '%s' "$2" | tr '[:upper:]' '[:lower:]' \
      | tr -cs 'a-z0-9' ' ' | sed 's/^ //; s/ $//'; } \
    | shasum -a 256 | cut -c1-12
}

sev_rank() {
  case "$1" in
    blocker) echo 3 ;;
    major) echo 2 ;;
    *) echo 1 ;;
  esac
}

[ $# -ge 2 ] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
CMD="$1"; DIR="$2"; shift 2
LEDGER="$DIR/ledger.jsonl"
ROUND_FILE="$DIR/round"

case "$CMD" in
  init)
    mkdir -p "$DIR"
    : > "$LEDGER"
    echo 1 > "$ROUND_FILE"
    echo "ledger initialized at $LEDGER (round 1)"
    ;;

  bump)
    [ -f "$ROUND_FILE" ] || die "not initialized: $DIR"
    r=$(( $(cat "$ROUND_FILE") + 1 ))
    echo "$r" > "$ROUND_FILE"
    echo "$r"
    ;;

  round)
    cat "$ROUND_FILE"
    ;;

  add)
    need_jq
    SOURCE=""
    FINDINGS=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --source) SOURCE="$2"; shift 2 ;;
        *) FINDINGS="$1"; shift ;;
      esac
    done
    [ -n "$SOURCE" ] || die "add: --source is required"
    [ -f "$FINDINGS" ] || die "add: findings file not found: $FINDINGS"
    [ -f "$LEDGER" ] || die "not initialized: $DIR"
    jq -e '.findings | type == "array"' "$FINDINGS" >/dev/null || die "add: $FINDINGS has no .findings array"
    # Reject malformed findings up front: an out-of-enum severity would rank
    # as minor in `converged` and silently slip under the gate.
    jq -e 'all(.findings[];
        (.severity | . == "blocker" or . == "major" or . == "minor")
        and (.file | type == "string" and length > 0)
        and (.title | type == "string" and length > 0)
        and (.body | type == "string"))' "$FINDINGS" >/dev/null \
      || die "add: $FINDINGS violates the findings schema (severity must be blocker|major|minor; file/title/body required)"
    ROUND="$(cat "$ROUND_FILE")"
    new=0; dup=0; reopened=0
    while IFS= read -r item; do
      file="$(printf '%s' "$item" | jq -r '.file')"
      title="$(printf '%s' "$item" | jq -r '.title')"
      fp="$(fingerprint "$file" "$title")"
      if grep -q "\"fp\":\"$fp\"" "$LEDGER"; then
        prev="$(jq -r --arg fp "$fp" \
          'select(.fp == $fp) | .status + "|" + (.last_seen_round | tostring)' "$LEDGER")"
        prev_status="${prev%%|*}"; prev_seen="${prev##*|}"
        if { [ "$prev_status" = fixed ] || [ "$prev_status" = rejected ] || [ "$prev_status" = wontfix ]; } \
           && [ "$prev_seen" -lt "$ROUND" ]; then
          reopened=$((reopened + 1))
          jq -c --arg fp "$fp" --arg src "$SOURCE" --argjson r "$ROUND" \
            'if .fp == $fp then .status = "open" | .last_seen_round = $r
               | .note = "reopened: re-reported by " + $src + " in round " + ($r | tostring)
             else . end' "$LEDGER" > "$LEDGER.tmp"
          mv "$LEDGER.tmp" "$LEDGER"
          echo "reopened $fp ($prev_status → open): $title"
        else
          dup=$((dup + 1))
          jq -c --arg fp "$fp" --argjson r "$ROUND" \
            'if .fp == $fp then .last_seen_round = $r else . end' "$LEDGER" > "$LEDGER.tmp"
          mv "$LEDGER.tmp" "$LEDGER"
        fi
      else
        new=$((new + 1))
        printf '%s' "$item" | jq -c --arg fp "$fp" --arg src "$SOURCE" --argjson r "$ROUND" \
          '{fp: $fp, round: $r, last_seen_round: $r, source: $src, status: "open",
            severity, file, line: (.line // null), title, body,
            confidence: (.confidence // null)}' >> "$LEDGER"
      fi
    done < <(jq -c '.findings[]' "$FINDINGS")
    open="$(jq -sc 'map(select(.status == "open")) | length' "$LEDGER")"
    echo "new=$new dup=$dup reopened=$reopened open=$open"
    ;;

  list)
    need_jq
    STATUS=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status) STATUS="$2"; shift 2 ;;
        *) die "list: unknown argument $1" ;;
      esac
    done
    if [ -n "$STATUS" ]; then
      jq -c --arg s "$STATUS" 'select(.status == $s)' "$LEDGER"
    else
      cat "$LEDGER"
    fi
    ;;

  resolve)
    need_jq
    [ $# -ge 2 ] || die "resolve: need <fp> <status>"
    FP="$1"; ST="$2"; shift 2
    NOTE=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --note) NOTE="$2"; shift 2 ;;
        *) die "resolve: unknown argument $1" ;;
      esac
    done
    case "$ST" in fixed|rejected|wontfix|contested|open) ;; *) die "resolve: bad status $ST" ;; esac
    grep -q "\"fp\":\"$FP\"" "$LEDGER" || die "resolve: fp not found: $FP"
    jq -c --arg fp "$FP" --arg st "$ST" --arg note "$NOTE" \
      'if .fp == $fp then .status = $st | (if $note != "" then .note = $note else . end) else . end' \
      "$LEDGER" > "$LEDGER.tmp"
    mv "$LEDGER.tmp" "$LEDGER"
    echo "$FP → $ST"
    ;;

  converged)
    need_jq
    CLEAN=1; MAX=3; GATE="major"
    while [ $# -gt 0 ]; do
      case "$1" in
        --clean-rounds) CLEAN="$2"; shift 2 ;;
        --max-rounds) MAX="$2"; shift 2 ;;
        --gate) GATE="$2"; shift 2 ;;
        *) die "converged: unknown argument $1" ;;
      esac
    done
    ROUND="$(cat "$ROUND_FILE")"
    gate_rank="$(sev_rank "$GATE")"
    open_blocking="$(jq -sc --argjson g "$gate_rank" '
      map(select((.status == "open" or .status == "contested")
        and ((if .severity == "blocker" then 3 elif .severity == "major" then 2 else 1 end) >= $g)))
      | length' "$LEDGER")"
    since=$(( ROUND - CLEAN ))
    new_recent="$(jq -sc --argjson since "$since" --argjson g "$gate_rank" '
      map(select(.round > $since
        and ((if .severity == "blocker" then 3 elif .severity == "major" then 2 else 1 end) >= $g)))
      | length' "$LEDGER")"
    echo "round=$ROUND open_blocking(>=$GATE)=$open_blocking new(>=$GATE)_in_last_${CLEAN}_rounds=$new_recent"
    if [ "$open_blocking" -eq 0 ] && [ "$new_recent" -eq 0 ] && [ "$ROUND" -ge "$CLEAN" ]; then
      echo "CONVERGED"
      exit 0
    fi
    if [ "$ROUND" -ge "$MAX" ]; then
      echo "MAX-ROUNDS EXHAUSTED (report remaining open findings honestly)"
      exit 3
    fi
    echo "NOT CONVERGED"
    exit 1
    ;;

  report)
    need_jq
    ROUND="$(cat "$ROUND_FILE" 2>/dev/null || echo '?')"
    echo "## Self-review ledger — round $ROUND"
    echo
    echo "| fp | sev | status | src | round | where | finding |"
    echo "|---|---|---|---|---|---|---|"
    jq -r '
      [.fp, .severity, .status, .source, (.round | tostring),
       (.file + (if .line then ":" + (.line | tostring) else "" end)),
       (.title | gsub("\\|"; "\\\\|"))]
      | "| " + join(" | ") + " |"' "$LEDGER"
    echo
    jq -sr '
      group_by(.status) | map("\(.[0].status): \(length)") | join(" · ")' "$LEDGER"
    ;;

  *)
    die "unknown command: $CMD"
    ;;
esac
