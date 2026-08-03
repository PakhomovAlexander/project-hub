#!/usr/bin/env bash
# brief-test.sh — behavioral test for the session-brief SessionStart hook.
#
# Fixtures small hubs, feeds the hook its stdin JSON, and asserts on the emitted
# additionalContext and the ./.scratch link: in-flight rows are injected condensed
# (placeholder rows dropped, capped at 12), the pointer line appears only when no
# rows exist, .scratch links to the session scratchpad and re-points per session,
# and a real (non-symlink) .scratch is never clobbered. The hook must exit 0 and
# stay silent when there is nothing to say.
#
# Run from the template repo root:  tests/brief-test.sh
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/template/.claude/hooks/session-brief.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for this test" >&2; exit 2; }

TMP="$(mktemp -d)"
SCRATCH_BASE="/tmp/claude-$(id -u)"
# shellcheck disable=SC2329  # invoked via the EXIT trap
cleanup() {
  for d in "$TMP/hub-a" "$TMP/hub-b" "$TMP/hub-c" "$TMP/hub-d"; do
    rm -rf "${SCRATCH_BASE:?}/$(printf '%s' "$d" | tr '/.' '--')" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

fail=0
must_contain() { # <file> <fixed-string>
  grep -qF -- "$2" "$1" || { printf 'FAIL missing   : %s\n' "$2"; fail=1; }
}
must_not_contain() { # <file> <fixed-string>
  ! grep -qF -- "$2" "$1" || { printf 'FAIL unexpected: %s\n' "$2"; fail=1; }
}
run_hook() { # <hub-dir> <session-id or "">; hook output on stdout
  if [ -n "$2" ]; then
    printf '{"session_id":"%s","hook_event_name":"SessionStart"}' "$2" \
      | CLAUDE_PROJECT_DIR="$1" bash "$HOOK"
  else
    CLAUDE_PROJECT_DIR="$1" bash "$HOOK" </dev/null
  fi
}
ctx_of() { # hook JSON on stdin → additionalContext text
  python3 -c 'import sys, json
print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'
}

# --- hub A: tracker with in-flight rows (incl. an unfilled placeholder row) --------
hub="$TMP/hub-a"
mkdir -p "$hub/docs"
today="$(date +%Y-%m-%d)"
cat > "$hub/docs/tracker.md" <<EOF
# acme tracker
**Snapshot:** $today — steady.

## In flight now

| Item | State | Where | Next action |
|------|-------|-------|-------------|
| Ship auth | ◐ | [ws](workstreams/auth.md) | land PR 42 |
| {{item}} | ◐ | {{link}} | {{next}} |
| Rotate keys | ⚠ | ops | waiting on human |

## Open decisions / gaps

- none
EOF

out="$TMP/out"; ctx="$TMP/ctx"
run_hook "$hub" "sess-aaaa-1111" > "$out"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL hub-a rc=$rc"; fail=1; }
ctx_of < "$out" > "$ctx" || { echo "FAIL hub-a: no additionalContext"; fail=1; }

must_contain "$ctx" "Tracker snapshot: $today (0d old)"
must_contain "$ctx" "In flight now (full board: docs/tracker.md):"
must_contain "$ctx" "◐ Ship auth — next: land PR 42"
must_contain "$ctx" "workstreams/auth.md"
must_contain "$ctx" "⚠ Rotate keys — next: waiting on human (ops)"
must_not_contain "$ctx" "{{"
must_not_contain "$ctx" "| Item |"
must_not_contain "$ctx" "Check docs/tracker.md for in-flight work"
must_contain "$ctx" "Scratch dir: ./.scratch"

[ -L "$hub/.scratch" ] || { echo "FAIL hub-a: .scratch is not a symlink"; fail=1; }
case "$(readlink "$hub/.scratch")" in
  */sess-aaaa-1111/scratchpad) : ;;
  *) echo "FAIL hub-a: .scratch points at $(readlink "$hub/.scratch")"; fail=1 ;;
esac
touch "$hub/.scratch/probe" || { echo "FAIL hub-a: .scratch not writable"; fail=1; }

# --- hub A again, new session: the link re-points ----------------------------------
run_hook "$hub" "sess-bbbb-2222" > "$out" || { echo "FAIL hub-a re-run rc"; fail=1; }
case "$(readlink "$hub/.scratch")" in
  */sess-bbbb-2222/scratchpad) : ;;
  *) echo "FAIL hub-a: .scratch did not re-point"; fail=1 ;;
esac

# --- hub A, .scratch is a REAL directory: never clobbered --------------------------
rm "$hub/.scratch"
mkdir "$hub/.scratch"; touch "$hub/.scratch/keepme"
run_hook "$hub" "sess-cccc-3333" > "$out" || { echo "FAIL hub-a real-dir rc"; fail=1; }
ctx_of < "$out" > "$ctx"
if [ -L "$hub/.scratch" ] || [ ! -f "$hub/.scratch/keepme" ]; then
  echo "FAIL hub-a: real .scratch dir was clobbered"; fail=1
fi
must_not_contain "$ctx" "Scratch dir: ./.scratch"

# --- hub B: tracker without an In-flight section → pointer fallback ----------------
hub="$TMP/hub-b"
mkdir -p "$hub/docs"
printf '# t\n**Snapshot:** %s — quiet.\n\n## Workstreams\n\nnone\n' "$today" > "$hub/docs/tracker.md"
run_hook "$hub" "sess-dddd-4444" > "$out" || { echo "FAIL hub-b rc"; fail=1; }
ctx_of < "$out" > "$ctx"
must_contain "$ctx" "Check docs/tracker.md for in-flight work before starting anything new."
must_not_contain "$ctx" "In flight now (full board"

# --- hub C: nothing to say and no session id → silent success ----------------------
hub="$TMP/hub-c"
mkdir -p "$hub"
out2="$(run_hook "$hub" "")"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL hub-c rc=$rc"; fail=1; }
[ -z "$out2" ] || { echo "FAIL hub-c: expected silence, got: $out2"; fail=1; }

# --- hub D: stale snapshot + 15 rows → STALE warning, cap at 12 --------------------
hub="$TMP/hub-d"
mkdir -p "$hub/docs"
{
  echo "# t"
  echo "**Snapshot:** 2026-01-01 — old."
  echo
  echo "## In flight now"
  echo
  echo "| Item | State | Where | Next action |"
  echo "|------|-------|-------|-------------|"
  i=1
  while [ "$i" -le 15 ]; do
    printf '| row%02d | ◐ | w | act%02d |\n' "$i" "$i"
    i=$((i + 1))
  done
} > "$hub/docs/tracker.md"
run_hook "$hub" "sess-eeee-5555" > "$out" || { echo "FAIL hub-d rc"; fail=1; }
ctx_of < "$out" > "$ctx"
must_contain "$ctx" "STALE: verify docs/tracker.md"
must_contain "$ctx" "◐ row01 — next: act01 (w)"
must_contain "$ctx" "◐ row12 — next: act12 (w)"
must_not_contain "$ctx" "row13"
must_contain "$ctx" "… and 3 more"

if [ "$fail" -eq 0 ]; then
  echo "OK — session-brief hook behaves."
else
  echo "FAIL — session-brief regressions above." >&2
fi
exit "$fail"
