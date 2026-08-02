#!/usr/bin/env bash
# ledger.sh — findings ledger for iterative review: dedup across rounds,
# status tracking, convergence check. Storage: <dir>/ledger.jsonl,
# <dir>/demands.jsonl, <dir>/round.
#
# Usage:
#   ledger.sh init       <dir>
#   ledger.sh bump       <dir>                          # round += 1, prints it
#   ledger.sh round      <dir>                          # print current round
#   ledger.sh add        <dir> --source <stage> <findings.json>
#   ledger.sh list       <dir> [--status open]          # JSONL to stdout
#   ledger.sh resolve    <dir> <fp> <fixed|rejected|wontfix|contested|open> [--note <text>]
#   ledger.sh unverified <dir> --source <stage>         # open claims that stage never disputed
#   ledger.sh demands    <dir> [--status open]          # benchmark demands, JSONL
#   ledger.sh demand     <dir> <id> <met|dropped|open> [--note <text>]
#   ledger.sh converged  <dir> [--clean-rounds 1] [--max-rounds 3] [--gate major]
#   ledger.sh report     <dir>                          # markdown summary
#
# add     appends findings not already fingerprinted (fp = hash of file+title)
#         and ingests the same file's `disputes` and `benchmark_demands`.
#         A duplicate of an entry resolved as FIXED is REOPENED with the
#         re-report's severity and evidence adopted — a re-report after a fix
#         means the fix didn't hold. This is NOT round-guarded: the gate is
#         re-run within a round after fixes, and that re-run is exactly where
#         a failed fix shows up. The cost of a stale same-round re-report is
#         one extra triage step (re-resolve it fixed); the cost of missing a
#         failed fix is shipping a broken change, so the loop errs toward
#         reopening. An open or contested duplicate re-reported at HIGHER
#         severity is ESCALATED the same way (adopt + news). rejected/wontfix
#         entries are NEVER auto-reopened — reviewers only see open claims, so
#         they will independently rediscover rejected ones forever; a
#         re-report there prints a re-triage warning and stays a dup (the
#         orchestrator decides, or the run would loop to exhaustion) — but a
#         higher-severity re-report adopts the new rank and evidence in place
#         AND counts as convergence news (severity is monotone, so this is
#         bounded), so a manual re-triage inherits the real severity and an
#         accepted fix still needs a clean round.
#         Prints "new=N dup=M reopened=R escalated=E open=K".
# unverified  the cross stage must return a `disputes` entry for every claim it
#         was given; this lists the open claims it did NOT address. Those are
#         UNVERIFIED, not confirmed — re-ask, or say so in the report.
# converged exit codes: 0 converged · 1 not yet · 3 max-rounds exhausted.
#         Only entries at/above --gate severity count as blocking or as
#         convergence-resetting news; sub-gate findings never force a round.
#         News is tracked per entry in news_round: set when a finding is
#         raised, reopened, or escalated, and CLEARED by resolving it
#         rejected/wontfix. A round that only produced false positives adds no
#         new external signal, so it must not buy itself another round; a
#         round that produced a FIX must, because the fix needs re-review.
set -euo pipefail

die() { echo "ledger.sh: $*" >&2; exit 2; }
need_jq() { command -v jq >/dev/null || die "jq is required"; }

# fp = exact file path + title normalized ONLY for case and whitespace.
# The path is untouched (src/foo-bar and src/foo_bar are different files);
# punctuation and non-ASCII stay significant ("x < 0" vs "x > 0", Cyrillic
# titles) — stripping them collapsed distinct findings into one entry.
fingerprint() {
  { printf '%s|' "$1"; printf '%s' "$2" | tr '[:upper:]' '[:lower:]' \
      | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; } \
    | shasum -a 256 | cut -c1-12
}

sev_rank() {
  case "$1" in
    blocker) echo 3 ;;
    major) echo 2 ;;
    *) echo 1 ;;
  esac
}

# Print the whole leading comment block (minus the shebang) as usage — a
# fixed line range silently truncates as the header grows.
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
[ $# -ge 2 ] || { usage; exit 2; }
CMD="$1"; DIR="$2"; shift 2
LEDGER="$DIR/ledger.jsonl"
DEMANDS="$DIR/demands.jsonl"
ROUND_FILE="$DIR/round"

# Every command but init needs a ledger; without this the failure surfaces as a
# raw `cat:`/`jq:` error from inside a pipeline instead of an actionable one.
need_init() {
  [ -f "$ROUND_FILE" ] || die "not initialized: $DIR (run: ledger.sh init $DIR)"
  [ -f "$LEDGER" ] || die "not initialized: $DIR (run: ledger.sh init $DIR)"
  # demands.jsonl is newer than ledger.jsonl — a ledger from an older run of
  # this script won't have one, so materialize it rather than failing.
  [ -f "$DEMANDS" ] || : > "$DEMANDS"
}

case "$CMD" in
  init)
    mkdir -p "$DIR"
    : > "$LEDGER"
    : > "$DEMANDS"
    echo 1 > "$ROUND_FILE"
    echo "ledger initialized at $LEDGER (round 1)"
    ;;

  bump)
    need_init
    r=$(( $(cat "$ROUND_FILE") + 1 ))
    echo "$r" > "$ROUND_FILE"
    echo "$r"
    ;;

  round)
    need_init
    cat "$ROUND_FILE"
    ;;

  add)
    need_jq
    need_init
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
    jq -e '.findings | type == "array"' "$FINDINGS" >/dev/null || die "add: $FINDINGS has no .findings array"
    # Reject malformed findings up front: an out-of-enum severity would rank
    # as minor in `converged` and silently slip under the gate. Empty
    # file/title strings are handled per finding below, not rejected here —
    # dying wholesale would throw away a whole valid batch over one entry.
    jq -e 'all(.findings[];
        (.severity | . == "blocker" or . == "major" or . == "minor")
        and (.file | type == "string")
        and (.title | type == "string")
        and (.body | type == "string"))' "$FINDINGS" >/dev/null \
      || die "add: $FINDINGS violates the findings schema (severity must be blocker|major|minor; file/title/body required)"
    ROUND="$(cat "$ROUND_FILE")"
    new=0; dup=0; reopened=0; escalated=0
    while IFS= read -r item; do
      file="$(printf '%s' "$item" | jq -r '.file')"
      title="$(printf '%s' "$item" | jq -r '.title')"
      case "$title" in
        *[![:space:]]*) ;;   # has at least one non-space char
        *)
          echo "ledger.sh: add: skipping finding with empty title (source=$SOURCE, file='$file')" >&2
          continue
          ;;
      esac
      [ -n "$file" ] || file="(change-wide)"
      fp="$(fingerprint "$file" "$title")"
      if grep -qF -- "\"fp\":\"$fp\"" "$LEDGER"; then
        prev="$(jq -r --arg fp "$fp" \
          'select(.fp == $fp) | .status + "|" + .severity' "$LEDGER")"
        prev_status="${prev%%|*}"; prev_sev="${prev##*|}"
        in_sev="$(printf '%s' "$item" | jq -r '.severity')"
        if [ "$prev_status" = rejected ] || [ "$prev_status" = wontfix ]; then
          # Not auto-reopened (see header) — but the orchestrator must see it,
          # and a HIGHER-severity re-report's rank and evidence are adopted in
          # place (status untouched): a manual re-triage to contested/open
          # must inherit the real rank, not the stale one it was rejected at.
          # Deliberately NOT round-guarded: stages ingest separately within a
          # round, and adoption is monotone — the second same-round re-report
          # may be the one carrying the blocker-grade evidence.
          dup=$((dup + 1))
          if [ "$(sev_rank "$in_sev")" -gt "$(sev_rank "$prev_sev")" ]; then
            # news_round = $r: the adoption is convergence news — if the
            # orchestrator accepts and fixes the escalated claim, the fix
            # must still survive a clean round like any other. Bounded churn:
            # severity is monotone, so a rejected entry can force at most two
            # such rounds over its lifetime.
            echo "ledger.sh: add: re-report of $prev_status finding $fp by $SOURCE at HIGHER severity ($prev_sev → $in_sev; evidence adopted) — re-triage manually if the rejection no longer holds: $title" >&2
            jq -c --arg fp "$fp" --arg src "$SOURCE" --argjson r "$ROUND" --argjson item "$item" \
              'if .fp == $fp then .news_round = $r | .last_seen_round = $r
                 | .severity = $item.severity | .line = ($item.line // .line)
                 | .body = $item.body | .confidence = ($item.confidence // null)
                 | .source = $src
               else . end' "$LEDGER" > "$LEDGER.tmp"
          else
            echo "ledger.sh: add: re-report of $prev_status finding $fp by $SOURCE — re-triage manually if the rejection no longer holds: $title" >&2
            jq -c --arg fp "$fp" --argjson r "$ROUND" \
              'if .fp == $fp then .last_seen_round = $r else . end' "$LEDGER" > "$LEDGER.tmp"
          fi
          mv "$LEDGER.tmp" "$LEDGER"
        elif [ "$prev_status" = fixed ]; then
          reopened=$((reopened + 1))
          # news_round = $r: a reopen is NEWS — converged must see a clean
          # round after the re-fix, exactly as for a brand-new finding.
          # The re-report is the CURRENT truth: adopt its severity, evidence
          # and source, or a round-1 minor re-reported as a blocker would
          # keep slipping under the gate on its stale severity.
          jq -c --arg fp "$fp" --arg src "$SOURCE" --argjson r "$ROUND" --argjson item "$item" \
            'if .fp == $fp then .status = "open" | .news_round = $r | .last_seen_round = $r
               | .severity = $item.severity | .line = ($item.line // .line)
               | .body = $item.body | .confidence = ($item.confidence // null)
               | .source = $src
               | .note = "reopened: re-reported by " + $src + " in round " + ($r | tostring)
             else . end' "$LEDGER" > "$LEDGER.tmp"
          mv "$LEDGER.tmp" "$LEDGER"
          echo "reopened $fp ($prev_status → open): $title"
        elif { [ "$prev_status" = open ] || [ "$prev_status" = contested ]; } \
             && [ "$(sev_rank "$in_sev")" -gt "$(sev_rank "$prev_sev")" ]; then
          # Same adopt-current-truth rule as reopen: an open (or contested)
          # finding re-reported at higher severity must not keep its stale
          # rank — and the escalation is convergence news.
          escalated=$((escalated + 1))
          jq -c --arg fp "$fp" --arg src "$SOURCE" --argjson r "$ROUND" --argjson item "$item" \
            'if .fp == $fp then .news_round = $r | .last_seen_round = $r
               | .severity = $item.severity | .line = ($item.line // .line)
               | .body = $item.body | .confidence = ($item.confidence // null)
               | .source = $src
               | .note = "escalated: re-reported as " + $item.severity + " by " + $src + " in round " + ($r | tostring)
             else . end' "$LEDGER" > "$LEDGER.tmp"
          mv "$LEDGER.tmp" "$LEDGER"
          echo "escalated $fp ($prev_sev → $in_sev): $title"
        else
          dup=$((dup + 1))
          jq -c --arg fp "$fp" --argjson r "$ROUND" \
            'if .fp == $fp then .last_seen_round = $r else . end' "$LEDGER" > "$LEDGER.tmp"
          mv "$LEDGER.tmp" "$LEDGER"
        fi
      else
        new=$((new + 1))
        # .round is the round the finding was first raised and never moves;
        # .news_round is the last round something newsworthy happened to it.
        printf '%s' "$item" | jq -c --arg fp "$fp" --arg src "$SOURCE" --arg f "$file" --argjson r "$ROUND" \
          '{fp: $fp, round: $r, news_round: $r, last_seen_round: $r, source: $src, status: "open",
            severity, file: $f, line: (.line // null), title, body,
            confidence: (.confidence // null), disputes: []}' >> "$LEDGER"
      fi
    done < <(jq -c '.findings[]' "$FINDINGS")

    # Disputes: this stage's verdicts on claims it was given. Recorded on the
    # disputed entry so `unverified` can name what it never addressed — an
    # unaddressed claim is unverified, not confirmed.
    dis=0; dis_unknown=0
    while IFS= read -r d; do
      dfp="$(printf '%s' "$d" | jq -r '.fp // ""')"
      dpos="$(printf '%s' "$d" | jq -r '.position // ""')"
      [ -n "$dfp" ] || continue
      case "$dpos" in
        confirm|refute) ;;
        *) echo "ledger.sh: add: dispute on $dfp has bad position '$dpos' (confirm|refute) — ignored" >&2; continue ;;
      esac
      if ! grep -qF -- "\"fp\":\"$dfp\"" "$LEDGER"; then
        dis_unknown=$((dis_unknown + 1))
        echo "ledger.sh: add: dispute references unknown fp $dfp (source=$SOURCE) — ignored" >&2
        continue
      fi
      dreason="$(printf '%s' "$d" | jq -r '.reason // ""')"
      # One dispute per source per finding: a re-review supersedes its own
      # earlier verdict rather than stacking a contradictory second one.
      jq -c --arg fp "$dfp" --arg src "$SOURCE" --arg pos "$dpos" --arg reason "$dreason" --argjson r "$ROUND" \
        'if .fp == $fp then
           .disputes = (((.disputes // []) | map(select(.source != $src)))
                        + [{source: $src, position: $pos, reason: $reason, round: $r}])
         else . end' "$LEDGER" > "$LEDGER.tmp"
      mv "$LEDGER.tmp" "$LEDGER"
      dis=$((dis + 1))
    done < <(jq -c '(.disputes // [])[]' "$FINDINGS")
    [ "$dis" -eq 0 ] && [ "$dis_unknown" -eq 0 ] || echo "disputes: recorded=$dis ignored=$dis_unknown"

    # Benchmark demands: a performance claim that must be measured before the
    # verdict can improve. Deduped by claim text so two stages demanding the
    # same measurement don't produce two runs.
    dem_new=0; dem_dup=0
    while IFS= read -r bd; do
      claim="$(printf '%s' "$bd" | jq -r '.claim // ""')"
      case "$claim" in
        *[![:space:]]*) ;;
        *) echo "ledger.sh: add: skipping benchmark demand with empty claim (source=$SOURCE)" >&2; continue ;;
      esac
      did="$(fingerprint demand "$claim")"
      if grep -qF -- "\"id\":\"$did\"" "$DEMANDS"; then
        dem_dup=$((dem_dup + 1))
      else
        dem_new=$((dem_new + 1))
        printf '%s' "$bd" | jq -c --arg id "$did" --arg src "$SOURCE" --argjson r "$ROUND" \
          '{id: $id, round: $r, source: $src, status: "open", claim,
            why: (.why // null), suggested_method: (.suggested_method // null)}' >> "$DEMANDS"
      fi
    done < <(jq -c '(.benchmark_demands // [])[]' "$FINDINGS")
    [ "$dem_new" -eq 0 ] && [ "$dem_dup" -eq 0 ] || echo "benchmark demands: new=$dem_new dup=$dem_dup"

    open="$(jq -sc 'map(select(.status == "open")) | length' "$LEDGER")"
    echo "new=$new dup=$dup reopened=$reopened escalated=$escalated open=$open"
    ;;

  list)
    need_jq
    need_init
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

  unverified)
    need_jq
    need_init
    SOURCE=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --source) SOURCE="$2"; shift 2 ;;
        *) die "unverified: unknown argument $1" ;;
      esac
    done
    [ -n "$SOURCE" ] || die "unverified: --source is required"
    jq -c --arg s "$SOURCE" '
      select((.status == "open" or .status == "contested")
        and ((.disputes // []) | map(select(.source == $s)) | length) == 0)' "$LEDGER"
    ;;

  demands)
    need_jq
    need_init
    STATUS=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status) STATUS="$2"; shift 2 ;;
        *) die "demands: unknown argument $1" ;;
      esac
    done
    if [ -n "$STATUS" ]; then
      jq -c --arg s "$STATUS" 'select(.status == $s)' "$DEMANDS"
    else
      cat "$DEMANDS"
    fi
    ;;

  demand)
    need_jq
    need_init
    [ $# -ge 2 ] || die "demand: need <id> <met|dropped|open>"
    ID="$1"; ST="$2"; shift 2
    NOTE=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --note) NOTE="$2"; shift 2 ;;
        *) die "demand: unknown argument $1" ;;
      esac
    done
    case "$ST" in met|dropped|open) ;; *) die "demand: bad status $ST (met|dropped|open)" ;; esac
    grep -qF -- "\"id\":\"$ID\"" "$DEMANDS" || die "demand: id not found: $ID"
    jq -c --arg id "$ID" --arg st "$ST" --arg note "$NOTE" \
      'if .id == $id then .status = $st | (if $note != "" then .note = $note else . end) else . end' \
      "$DEMANDS" > "$DEMANDS.tmp"
    mv "$DEMANDS.tmp" "$DEMANDS"
    echo "$ID → $ST"
    ;;

  resolve)
    need_jq
    need_init
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
    grep -qF -- "\"fp\":\"$FP\"" "$LEDGER" || die "resolve: fp not found: $FP"
    ROUND="$(cat "$ROUND_FILE")"
    # news_round: rejecting a finding (or parking it as wontfix) produces no
    # new external signal, so it must not buy the run another round — clear it.
    # A FIX keeps its news (the new code needs re-review); a manual reopen
    # re-arms it.
    case "$ST" in
      rejected|wontfix) NEWS=0 ;;
      open) NEWS="$ROUND" ;;
      *) NEWS="" ;;
    esac
    jq -c --arg fp "$FP" --arg st "$ST" --arg note "$NOTE" --arg news "$NEWS" \
      'if .fp == $fp then .status = $st
         | (if $news != "" then .news_round = ($news | tonumber) else . end)
         | (if $note != "" then .note = $note else . end)
       else . end' \
      "$LEDGER" > "$LEDGER.tmp"
    mv "$LEDGER.tmp" "$LEDGER"
    echo "$FP → $ST"
    ;;

  converged)
    need_jq
    need_init
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
    # news_round, not round: a finding rejected as a false positive has its
    # news cleared, so a round that found only false positives doesn't force
    # another one. (// .round keeps ledgers written by an older version working.)
    new_recent="$(jq -sc --argjson since "$since" --argjson g "$gate_rank" '
      map(select((.news_round // .round) > $since
        and ((if .severity == "blocker" then 3 elif .severity == "major" then 2 else 1 end) >= $g)))
      | length' "$LEDGER")"
    open_demands="$(jq -sc 'map(select(.status == "open")) | length' "$DEMANDS")"
    echo "round=$ROUND open_blocking(>=$GATE)=$open_blocking new(>=$GATE)_in_last_${CLEAN}_rounds=$new_recent open_demands=$open_demands"
    if [ "$open_demands" -gt 0 ]; then
      echo "note: $open_demands benchmark demand(s) still open — measure them or record why not (ledger.sh demand <id> met|dropped)" >&2
    fi
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
    need_init
    ROUND="$(cat "$ROUND_FILE")"
    echo "## Self-review ledger — round $ROUND"
    echo
    echo "| fp | sev | status | src | round | where | finding | disputes |"
    echo "|---|---|---|---|---|---|---|---|"
    jq -r '
      [.fp, .severity, .status, .source, (.round | tostring),
       (.file + (if .line then ":" + (.line | tostring) else "" end)),
       (.title | gsub("\\|"; "\\\\|")),
       ((.disputes // []) | map(.source + ":" + .position) | join(" ") | if . == "" then "—" else . end)]
      | "| " + join(" | ") + " |"' "$LEDGER"
    echo
    jq -sr '
      if length == 0 then "no findings"
      else group_by(.status) | map("\(.[0].status): \(length)") | join(" · ") end' "$LEDGER"
    if [ -s "$DEMANDS" ]; then
      echo
      echo "### Benchmark demands"
      echo
      echo "| id | status | src | claim |"
      echo "|---|---|---|---|"
      jq -r '[.id, .status, .source, (.claim | gsub("\\|"; "\\\\|"))] | "| " + join(" | ") + " |"' "$DEMANDS"
    fi
    ;;

  *)
    die "unknown command: $CMD"
    ;;
esac
