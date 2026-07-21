#!/usr/bin/env bash
# codex-review.sh — cross-model review stage via the Codex CLI, non-interactive.
#
# Usage:
#   codex-review.sh [-C <repo>] --prompt-file <f> --out <file>
#                   [--mode exec|review] [--model <m>] [--effort <e>]
#                   [--schema <file>] [--base <ref>] [--uncommitted]
#
#   exec   (default) codex exec in a READ-ONLY sandbox; the final answer must
#          match --schema (default: findings.schema.json next to this script)
#          and is written to --out as JSON. Full session log: <out>.log
#   review           codex review (native reviewer) against --base or
#          --uncommitted, with --prompt-file as custom instructions; prose
#          output captured to --out.
#
# Exit code: codex's own exit code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="."
PROMPT_FILE=""
OUT=""
MODE="exec"
MODEL="gpt-5.6-sol"
EFFORT="xhigh"
SCHEMA="$SCRIPT_DIR/findings.schema.json"
BASE=""
UNCOMMITTED=0

while [ $# -gt 0 ]; do
  case "$1" in
    -C) REPO="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --schema) SCHEMA="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --uncommitted) UNCOMMITTED=1; shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "codex-review.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then echo "codex-review.sh: --prompt-file is required and must exist" >&2; exit 2; fi
[ -n "$OUT" ] || { echo "codex-review.sh: --out is required" >&2; exit 2; }
command -v codex >/dev/null || { echo "codex-review.sh: codex CLI not found" >&2; exit 127; }

if [ "$MODE" = "exec" ]; then
  [ -f "$SCHEMA" ] || { echo "codex-review.sh: schema not found: $SCHEMA" >&2; exit 2; }
  rc=0
  codex exec -C "$REPO" -s read-only --skip-git-repo-check --color never \
    -m "$MODEL" -c "model_reasoning_effort=$EFFORT" -c "approval_policy=never" \
    --output-schema "$SCHEMA" -o "$OUT" \
    - < "$PROMPT_FILE" > "$OUT.log" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "codex exec failed (rc=$rc); last log lines:" >&2
    tail -20 "$OUT.log" >&2
    exit "$rc"
  fi
  # Sanity: the answer must be parseable JSON with a findings array.
  jq -e '.findings | type == "array"' "$OUT" >/dev/null 2>&1 \
    || { echo "codex-review.sh: $OUT is not valid findings JSON" >&2; exit 3; }
  echo "codex findings: $(jq '.findings | length' "$OUT") · verdict: $(jq -r '.verdict // "n/a"' "$OUT") → $OUT"
else
  args=( review -c "model=$MODEL" -c "model_reasoning_effort=$EFFORT" )
  if [ "$UNCOMMITTED" -eq 1 ]; then
    args+=( --uncommitted )
  elif [ -n "$BASE" ]; then
    args+=( --base "$BASE" )
  fi
  rc=0
  ( cd "$REPO" && codex "${args[@]}" - < "$PROMPT_FILE" ) > "$OUT" 2>"$OUT.log" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "codex review failed (rc=$rc); last log lines:" >&2
    tail -20 "$OUT.log" >&2
    exit "$rc"
  fi
  echo "codex review captured → $OUT"
fi
