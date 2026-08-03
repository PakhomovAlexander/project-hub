#!/usr/bin/env bash
# Claude Code SessionStart hook — the cockpit greets the pilot.
#
# Injects a short situational brief into every new session: the tracker's snapshot
# date (with a staleness warning past 7 days), the tracker's **In flight now** rows
# (condensed — the brief answers "what's live?" instead of pointing at a 10k-token
# file), and the linked repos' branch/dirty state. It also links `./.scratch` to
# this session's scratchpad, so agents get a short stable temp path instead of
# re-typing a ~95-char absolute one on every command.
#
# Degrades gracefully — a single-repo hub (no repos.manifest) skips the repo
# status, a missing tracker skips the date, a tracker without in-flight rows falls
# back to a pointer — and never blocks the session (exit 0).
#
# Generic as-is; no project-specific edits needed.
set -u

HUB="${CLAUDE_PROJECT_DIR:-$PWD}"

# Hook stdin is a JSON object; only session_id is used (for the .scratch link).
stdin_json="$(cat 2>/dev/null || true)"
sid=""
if [ -n "$stdin_json" ]; then
  if command -v jq >/dev/null 2>&1; then
    sid="$(printf '%s' "$stdin_json" | jq -r '.session_id // empty' 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    sid="$(printf '%s' "$stdin_json" | python3 -c 'import sys, json
print(json.load(sys.stdin).get("session_id") or "")' 2>/dev/null || true)"
  fi
  # Path component only — drop anything that isn't [A-Za-z0-9._-], and any leading dots.
  sid="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-' | sed 's/^\.*//')"
fi

brief=""
append() { brief="${brief}
$1"; }

# Tracker snapshot age + in-flight rows --------------------------------------------
tracker="$HUB/docs/tracker.md"
inflight=""
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
    append "$line"
  else
    append "docs/tracker.md has no dated Snapshot line — treat its contents as unverified."
  fi

  # Condense the "## In flight now" table: data rows only (header, separator, and
  # unfilled placeholder rows dropped), columns resolved by header name so a hub
  # that reordered them still reads right. Capped at 12 rows to keep the brief
  # cheap; the full board stays one Read away.
  inflight="$(awk -F'|' '
    BEGIN { n = 0; header = 0; ci = 0; cs = 0; cw = 0; cn = 0
            ph = sprintf("%c%c", 123, 123) }          # literal double-brace
    /^## /            { infl = ($0 ~ /^## In flight now/) ? 1 : 0; next }
    infl != 1         { next }
    $0 !~ /^\|/       { next }
    $0 ~ /^[| :-]+$/  { next }                        # separator / empty row
    index($0, ph) > 0 { next }                        # unfilled template row
    { for (i = 1; i <= NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
    header == 0 {
      header = 1
      for (i = 1; i <= NF; i++) {
        h = tolower($i)
        if (h == "item") ci = i
        else if (h == "state") cs = i
        else if (h == "where") cw = i
        else if (h ~ /^next/) cn = i
      }
      if (ci == 0) { ci = 2; cs = 3; cw = 4; cn = 5 } # stock column order
      next
    }
    {
      item = (ci <= NF) ? $ci : ""
      state = (cs > 0 && cs <= NF) ? $cs : ""
      whr = (cw > 0 && cw <= NF) ? $cw : ""
      nxt = (cn > 0 && cn <= NF) ? $cn : ""
      if (item == "" && nxt == "") next
      row = (state != "") ? state " " item : item
      if (nxt != "") row = row " — next: " nxt
      if (whr != "") row = row " (" whr ")"
      gsub(/\]\(/, " (", row); gsub(/[][]/, "", row)  # [text](url) → text (url)
      if (length(row) > 200) row = substr(row, 1, 197) "…"
      n++
      if (n <= 12) rows[n] = row
    }
    END {
      for (i = 1; i <= n && i <= 12; i++) print rows[i]
      if (n > 12) printf "… and %d more\n", n - 12
    }' "$tracker" 2>/dev/null || true)"
  if [ -n "$inflight" ]; then
    append "In flight now (full board: docs/tracker.md):
$inflight"
  fi
fi

# Linked repos branch/dirty state --------------------------------------------------
if [ -f "$HUB/repos.manifest" ] && [ -f "$HUB/scripts/repos.sh" ]; then
  status="$(bash "$HUB/scripts/repos.sh" --status 2>/dev/null || true)"
  if [ -n "$status" ]; then
    append "Linked repos (make status):
$status"
  fi
fi

if [ -f "$tracker" ] && [ -z "$inflight" ]; then
  append "Check docs/tracker.md for in-flight work before starting anything new."
fi

# ./.scratch → this session's scratchpad -------------------------------------------
# Env vars don't survive between tool calls, so without this the long scratchpad
# path gets re-typed forever. The target follows the harness's own convention
# (/tmp/claude-<uid>/<cwd slug>/<session_id>/scratchpad — a Claude Code detail);
# if the harness didn't pre-create it, mkdir makes the same directory, so .scratch
# is usable either way. Untracked (.gitignore), so each worktree gets its own;
# two live sessions on ONE checkout re-point it to the newer session — harmless
# for scratch data. Never clobbers a real (non-symlink) .scratch.
if [ -n "$sid" ]; then
  target="/tmp/claude-$(id -u)/$(printf '%s' "$HUB" | tr '/.' '--')/$sid/scratchpad"
  if [ ! -e "$HUB/.scratch" ] || [ -L "$HUB/.scratch" ]; then
    if mkdir -p "$target" 2>/dev/null && ln -sfn "$target" "$HUB/.scratch" 2>/dev/null; then
      append "Scratch dir: ./.scratch (→ this session's scratchpad; gitignored)"
    fi
  fi
fi

[ -n "$brief" ] || exit 0
brief="Hub session brief —$brief"

# Emit as SessionStart additionalContext (jq if available, else python3).
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$brief" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}))' "$brief"
fi
exit 0
