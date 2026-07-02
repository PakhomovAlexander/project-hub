#!/usr/bin/env bash
# Claude Code SessionStart hook — the cockpit greets the pilot.
#
# Injects a short situational brief into every new session: the tracker's snapshot
# date (with a staleness warning past 7 days) and the linked repos' branch/dirty
# state. Degrades gracefully — a single-repo hub (no repos.manifest) skips the repo
# status, a missing tracker skips the date — and never blocks the session (exit 0).
#
# Generic as-is; no project-specific edits needed.
set -u

HUB="${CLAUDE_PROJECT_DIR:-$PWD}"
brief=""

# Tracker snapshot age -----------------------------------------------------------
tracker="$HUB/docs/tracker.md"
if [ -f "$tracker" ]; then
  snap="$(grep -m1 'Snapshot:' "$tracker" 2>/dev/null | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1 || true)"
  if [ -n "${snap:-}" ]; then
    age="$(python3 -c 'import sys, datetime
d = datetime.date.fromisoformat(sys.argv[1])
print((datetime.date.today() - d).days)' "$snap" 2>/dev/null || true)"
    line="Tracker snapshot: $snap"
    if [ -n "${age:-}" ]; then
      line="$line (${age}d old)"
      [ "$age" -gt 7 ] 2>/dev/null && line="$line — STALE: verify docs/tracker.md against reality before trusting it"
    fi
    brief="$line"
  else
    brief="docs/tracker.md has no dated Snapshot line — treat its contents as unverified."
  fi
fi

# Linked repos branch/dirty state --------------------------------------------------
if [ -f "$HUB/repos.manifest" ] && [ -f "$HUB/scripts/repos.sh" ]; then
  status="$(bash "$HUB/scripts/repos.sh" --status 2>/dev/null || true)"
  if [ -n "$status" ]; then
    brief="$brief
Linked repos (make status):
$status"
  fi
fi

[ -n "$brief" ] || exit 0
brief="Hub session brief —
$brief
Check docs/tracker.md for in-flight work before starting anything new."

# Emit as SessionStart additionalContext (jq if available, else python3).
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$brief" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}))' "$brief"
fi
exit 0
