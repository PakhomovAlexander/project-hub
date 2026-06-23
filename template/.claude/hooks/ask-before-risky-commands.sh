#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) gate — {{PROJECT_NAME}} Project Hub.
#
# Prompts before prod-affecting / destructive commands in ANY wrapper form
# (env VAR=val …, tool -C <dir> …, chained with ; && |, multi-line); auto-allows
# everything else. This keeps day-to-day work friction-free while putting a human in
# the loop for the commands that can change prod or destroy state.
#
# TEMPLATE: edit RISKY_WORDS for your project. The defaults cover common infra/cloud
# tooling and `git push` / `docker push`. Add your own (e.g. a deploy CLI), or trim what
# you don't use. Auto-allowing everything else means destructive *shell* commands (rm -rf,
# etc.) are NOT gated here — agents are expected to be careful; tighten if you want.
set -u

# --- the watchlist: command words that should prompt before running ----------------
RISKY_WORDS="aws|gcloud|az|kubectl|helm|terraform|terragrunt"
# -----------------------------------------------------------------------------------

# Pull the command out of the hook's stdin JSON (jq if available, else python3).
if command -v jq >/dev/null 2>&1; then
  cmd="$(jq -r '.tool_input.command // ""' 2>/dev/null)"
else
  cmd="$(python3 -c 'import sys, json; print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))' 2>/dev/null)"
fi

# Couldn't read the command → stay neutral, let normal permission rules decide (fail safe).
[ -z "$cmd" ] && exit 0

# ERE, matched line-by-line: a risky word as a command (after start / space / ; & | () ;
# plus `git … push` and `docker … push` allowing global options before the subcommand.
re="(^|[[:space:];&|(])(${RISKY_WORDS})([[:space:]]|$)"
re="$re"'|(^|[[:space:];&|(])(git|docker)([[:space:]]+(-[A-Za-z-]+|[-_A-Za-z0-9]+=[^[:space:]]+|-C[[:space:]]+[^[:space:]]+))*[[:space:]]+push([[:space:]]|$)'

if printf '%s\n' "$cmd" | grep -Eq "$re"; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Prod-affecting / destructive command — confirm before running."}}'
else
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
fi
