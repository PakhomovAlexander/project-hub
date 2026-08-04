#!/usr/bin/env bash
# stats-test.sh — session-stats.sh against a synthetic transcript.
#
# Builds a small ~/.claude/projects-style directory by hand (one session file, one
# agent-* subagent file, one malformed line) with known token counts, timestamps,
# commands, and errors — then asserts the aggregates: request/turn totals, peak
# context, the >60min idle-resume bucket, the permission-gate read-only/mutating
# split (families parsed from the template's own hook), tool-error classes,
# repeated-command counts, and the parse-failure note. Also: no transcripts → a
# clear failure, not a crash.
#
# Run from the template repo root:  tests/stats-test.sh
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATS="$ROOT/template/scripts/session-stats.sh"
[ -f "$STATS" ] || { echo "script not found: $STATS" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for this test" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TX="$TMP/tx"
mkdir -p "$TX" "$TMP/empty"

# One session: 9 main-chain requests. Peak context 180101. A 2h04m idle gap before
# the 12:05 request (cache-write 180000). "cd …" runs 6× identically. One tool
# error ("has not been read yet"), one malformed line, one human turn.
cat > "$TX/aabbccdd-1111.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-08-01T10:00:00.000Z","message":{"role":"user","content":"please fix the thing"}}
{"type":"assistant","timestamp":"2026-08-01T10:00:05.000Z","message":{"role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":1000,"cache_read_input_tokens":50000,"output_tokens":50},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"kubectl get pods -n prod"}}]}}
{"type":"user","timestamp":"2026-08-01T10:00:07.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"3 pods"}]}}
{"type":"assistant","timestamp":"2026-08-01T10:01:00.000Z","message":{"role":"assistant","usage":{"input_tokens":5,"cache_creation_input_tokens":200,"cache_read_input_tokens":150000,"output_tokens":20},"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"kubectl delete pod x"}}]}}
{"type":"user","timestamp":"2026-08-01T10:01:05.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"File has not been read yet. Read it first."}]}}
{"type":"assistant","timestamp":"2026-08-01T12:05:00.000Z","message":{"role":"assistant","usage":{"input_tokens":5,"cache_creation_input_tokens":180000,"cache_read_input_tokens":0,"output_tokens":10},"content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"cd /very/long/scratch/path && ls"}}]}}
{"type":"assistant","timestamp":"2026-08-01T12:06:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":100,"cache_read_input_tokens":180000,"output_tokens":5},"content":[{"type":"tool_use","id":"t4","name":"Bash","input":{"command":"cd /very/long/scratch/path && ls"}}]}}
{"type":"assistant","timestamp":"2026-08-01T12:07:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":100,"cache_read_input_tokens":180000,"output_tokens":5},"content":[{"type":"tool_use","id":"t5","name":"Bash","input":{"command":"cd /very/long/scratch/path && ls"}}]}}
{"type":"assistant","timestamp":"2026-08-01T12:08:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":100,"cache_read_input_tokens":180000,"output_tokens":5},"content":[{"type":"tool_use","id":"t6","name":"Bash","input":{"command":"cd /very/long/scratch/path && ls"}}]}}
{"type":"assistant","timestamp":"2026-08-01T12:09:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":100,"cache_read_input_tokens":180000,"output_tokens":5},"content":[{"type":"tool_use","id":"t7","name":"Bash","input":{"command":"cd /very/long/scratch/path && ls"}}]}}
{"type":"assistant","timestamp":"2026-08-01T12:10:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":100,"cache_read_input_tokens":180000,"output_tokens":5},"content":[{"type":"tool_use","id":"t8","name":"Bash","input":{"command":"cd /very/long/scratch/path && ls"}}]}}
this is not json
{"type":"assistant","timestamp":"2026-08-01T12:11:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":50,"cache_read_input_tokens":180000,"output_tokens":99},"content":[{"type":"text","text":"done"}]}}
EOF

# A subagent transcript: counted as subagent requests, not as a session.
cat > "$TX/agent-zz01.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-08-01T10:30:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000,"output_tokens":1},"content":[{"type":"tool_use","id":"a1","name":"Bash","input":{"command":"echo sub1"}}]}}
{"type":"assistant","timestamp":"2026-08-01T10:31:00.000Z","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000,"output_tokens":1},"content":[{"type":"tool_use","id":"a2","name":"Bash","input":{"command":"echo sub2"}}]}}
EOF

fail=0
must_contain() { # <file> <fixed-string>
  grep -qF -- "$2" "$1" || { printf 'FAIL missing   : %s\n' "$2"; fail=1; }
}
must_match() { # <file> <ERE>
  grep -qE -- "$2" "$1" || { printf 'FAIL no match  : %s\n' "$2"; fail=1; }
}

out="$TMP/out"
bash "$STATS" "$TX" > "$out" 2> "$TMP/err"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL rc=$rc"; sed 's/^/  stderr: /' "$TMP/err"; fail=1; }

# sessions + totals
must_match   "$out" 'aabbccdd .* 180k +2\.2h +1'
must_contain "$out" "totals: 1 sessions · 9 requests (+2 subagent) · 1 human turns · median session span 2.2h"
must_contain "$out" "per human turn: 10.0 tool calls, 11.0 requests"
# context bands (11 assistant requests total: 3 below 100k, 8 in 100–200k)
must_match   "$out" '100–200k: +8 requests \(73%\)'
# idle resume: one 2h gap whose request wrote 180k cache tokens
must_contain "$out" "1 idle-resume requests · avg cache-write 180k tokens each"
# permission-gate split, families read from the template's own hook
must_contain "$out" "kubectl|helm"
must_contain "$out" "matching a gated family: 2 (20%)"
must_contain "$out" "read-only: 1 (50%) · mutating: 1 · unclassified: 0"
# tool errors
must_contain "$out" "==> tool errors (1)"
must_contain "$out" "file-not-read (Read before Edit/Write)"
# repeated commands
must_contain "$out" "5 redundant re-runs across 10 Bash calls"
must_contain "$out" "6× cd /very/long/scratch/path && ls"
# format-drift + privacy notes
must_contain "$out" "1 transcript line(s) failed to parse"
must_contain "$out" "nothing was written or uploaded"

# no transcripts → clear failure, not a crash
if bash "$STATS" "$TMP/empty" > "$TMP/out2" 2> "$TMP/err2"; then
  echo "FAIL: empty dir should exit non-zero"; fail=1
fi
must_contain "$TMP/err2" "no .jsonl transcripts found"
# a missing path is skipped with a note (and doesn't crash the run)
bash "$STATS" "$TX" "$TMP/nope" > "$TMP/out3" 2> "$TMP/err3" || { echo "FAIL: missing-path run rc"; fail=1; }
must_contain "$TMP/err3" "skipping (not found)"

if [ "$fail" -eq 0 ]; then
  echo "OK — session-stats aggregates are right."
else
  echo "FAIL — session-stats regressions above." >&2
fi
exit "$fail"
