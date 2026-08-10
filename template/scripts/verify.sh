#!/usr/bin/env bash
# verify.sh — sanity-check this Project Hub.
#
# Ships inside every generated hub (scripts/verify.sh) and doubles as the check the
# template repo's scripts/verify-hub.sh runs against a freshly generated hub. It is
# the local, one-shot form of what docs CI enforces on every PR — run it before
# pushing doc changes, or via the /verify skill.
#
#   scripts/verify.sh            # check the current directory
#   scripts/verify.sh <hub-dir>  # check another hub
#
# Checks (fail):
#   1. no leftover double-brace placeholder tokens or template guidance markers
#      (files named _template.md keep them by design and are exempt)
#   2. hooks + shell scripts (including skill scripts) are executable; the
#      .claude/skills link resolves
#   3. relative markdown links resolve to a real file
#   4. no markdown links INTO repos/ — it is gitignored, so such links break in CI
#      and on fresh clones; cite those paths as inline code instead
#   5. .hub-meta.yml provenance present and resolved — /update-hub depends on it
#   6. tests/smoke-*.mjs pass when verifying this script's own hub; an external
#      target is inspected but its code is never executed
# Warns (never fail):
#   7. docs/tracker.md snapshot date is old, missing, or older than the file's
#      latest committed edit
#
# Portable: runs under macOS stock bash 3.2 (no mapfile / associative arrays).
set -u

HUB="${1:-.}"
if [ ! -d "$HUB" ]; then
  echo "not a directory: $HUB" >&2
  exit 2
fi
HUB="$(cd -- "$HUB" >/dev/null 2>&1 && pwd -P)"

fail=0
note() { printf '  %s\n' "$1"; }

# Pattern built in pieces so this script never matches itself when scanned.
ph='\{\{|TEMPL'
ph="${ph}ATE:"

# 1: leftover placeholders / template guidance markers --------------------------------
echo "==> leftover placeholders / template markers"
hits="$(grep -rnE "$ph" "$HUB" \
  --include='*.md' --include='*.sh' --include='*.json' --include='*.manifest' 2>/dev/null \
  | grep -v '/_template\.md:' || true)"
if [ -n "$hits" ]; then
  fail=1
  while IFS= read -r l; do note "$l"; done <<EOF
$hits
EOF
else
  note "clean"
fi

# 2: hooks + scripts executable, skills link resolves ---------------------------------
echo "==> hooks, scripts, skills"
hookbad=0
hook="$HUB/.claude/hooks/ask-before-risky-commands.sh"
if [ ! -f "$hook" ]; then
  note "MISSING: $hook"; hookbad=1
fi
script_files="$(
  find "$HUB/scripts" "$HUB/.claude/hooks" -maxdepth 1 -type f -name '*.sh' 2>/dev/null
  # Skills ship scripts too, at their own depth. /update-hub copies new
  # template files in by writing them, which drops the exec bit — without
  # this the hub gets a skill whose scripts silently cannot run.
  find "$HUB/.agents/skills" -type f -name '*.sh' 2>/dev/null
)"
while IFS= read -r s; do
  [ -n "$s" ] || continue
  [ -x "$s" ] || { note "NOT EXECUTABLE: chmod +x ${s#"$HUB"/}"; hookbad=1; }
done <<EOF
$script_files
EOF
skills="$HUB/.claude/skills"
if [ -L "$skills" ] && [ ! -e "$skills" ]; then
  note "BROKEN LINK: .claude/skills points nowhere (expected ../.agents/skills)"; hookbad=1
fi
if [ "$hookbad" -eq 0 ]; then note "ok"; else fail=1; fi

# 3 + 4: relative markdown links resolve; none point into repos/ ----------------------
echo "==> internal markdown links"
linkbad=0
while IFS= read -r f; do
  dir="$(dirname -- "$f")"
  while IFS= read -r tgt; do
    case "$tgt" in http*|mailto:*|\#*|"") continue ;; esac
    path="${tgt%%#*}"                 # strip #anchor
    [ -z "$path" ] && continue
    case "$path" in
      /*) resolved="$HUB$path" ;;     # hub-absolute (rare)
      *)  resolved="$dir/$path" ;;
    esac
    # normalize ../ segments so "under repos/?" is a real prefix test
    if command -v python3 >/dev/null 2>&1; then
      norm="$(python3 -c 'import os, sys; print(os.path.normpath(sys.argv[1]))' "$resolved" 2>/dev/null || printf '%s' "$resolved")"
    else
      norm="$resolved"
    fi
    case "$norm" in
      "$HUB"/repos/*|"$HUB"/repos)
        note "$f → links into repos/: $tgt  (repos/ is gitignored — this breaks docs CI; cite it as inline code)"
        linkbad=1
        continue
        ;;
    esac
    if [ ! -e "$norm" ]; then
      note "$f → broken link: $tgt"
      linkbad=1
    fi
  done < <(grep -oE '\]\([^)#][^)]*\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done < <(find "$HUB" -type f -name '*.md' \
  -not -path '*/.git/*' -not -path '*/node_modules/*' -not -name '_template.md' | sort)
[ "$linkbad" -eq 0 ] && note "all resolve" || fail=1

# 5: template provenance — /update-hub depends on it -----------------------------------
echo "==> template provenance (.hub-meta.yml)"
meta="$HUB/.hub-meta.yml"
metabad=0
if [ ! -f "$meta" ]; then
  note "MISSING: .hub-meta.yml — the hub can't take template updates; backfill it (shape: template/.hub-meta.yml in the template repo; runbook: its UPDATE.md)"
  metabad=1
else
  grep -qE '^[[:space:]]*url:[[:space:]]*[^[:space:]]' "$meta" \
    || { note "INCOMPLETE: .hub-meta.yml has no template url"; metabad=1; }
  grep -qE '^[[:space:]]*sha:[[:space:]]*[^[:space:]]' "$meta" \
    || { note "INCOMPLETE: .hub-meta.yml has no template sha"; metabad=1; }
  if grep -E "$ph" "$meta" >/dev/null 2>&1; then
    note "UNRESOLVED: .hub-meta.yml still holds placeholder tokens — fill the real url / sha / layout"
    metabad=1
  fi
fi
if [ "$metabad" -eq 0 ]; then note "ok"; else fail=1; fi

# 6: workflow smoke tests --------------------------------------------------------------
echo "==> workflow smoke tests"
# verify.sh accepts a directory argument and may therefore inspect a hub whose code
# the caller did not authorize. Execute tests only when the target is the hub that
# owns this verifier; the template's verify-hub.sh wrapper remains inspection-only.
smoke_found=0
node_available=0
command -v node >/dev/null 2>&1 && node_available=1
own_hub="$(cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd -P)"
if [ "$HUB" != "$own_hub" ]; then
  note "SKIP: external hub inspected without executing its smoke tests"
else
  for smoke_test in "$HUB"/tests/smoke-*.mjs; do
    [ -f "$smoke_test" ] || continue
    smoke_found=1
    if [ "$node_available" -eq 0 ]; then
      continue
    fi
    if smoke_output="$(cd -- "$HUB" && node "$smoke_test" 2>&1)"; then
      note "pass: $(basename -- "$smoke_test")"
    else
      fail=1
      note "FAIL: $(basename -- "$smoke_test")"
      smoke_hits="$(printf '%s\n' "$smoke_output" \
        | grep -E '^[[:space:]]+FAIL|failing assertion' || true)"
      [ -n "$smoke_hits" ] \
        || smoke_hits="$(printf '%s\n' "$smoke_output" | tail -n 12)"
      while IFS= read -r smoke_line; do
        note "  $smoke_line"
      done <<EOF
$smoke_hits
EOF
    fi
  done
  if [ "$smoke_found" -eq 0 ]; then
    note "no tests/smoke-*.mjs (skipped)"
  elif [ "$node_available" -eq 0 ]; then
    fail=1
    note "FAIL: workflow smoke tests exist but node is unavailable"
  fi
fi

# 7: tracker freshness (warn only) -----------------------------------------------------
echo "==> tracker freshness (warning only)"
tracker="$HUB/docs/tracker.md"
if [ -f "$tracker" ]; then
  snap="$(grep -m1 'Snapshot:' "$tracker" 2>/dev/null | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1 || true)"
  if [ -z "${snap:-}" ]; then
    note "WARN: docs/tracker.md has no dated Snapshot line"
  else
    git_root="$(git -C "$HUB" rev-parse --show-toplevel 2>/dev/null || true)"
    gitdate=""
    if [ "$git_root" = "$HUB" ]; then
      gitdate="$(git -C "$HUB" log -1 --format=%cd --date=short \
        -- docs/tracker.md 2>/dev/null || true)"
    fi
    if [ -n "${gitdate:-}" ] && [ "$gitdate" \> "$snap" ]; then
      note "WARN: tracker edited $gitdate but its Snapshot line still says $snap — refresh it (/tracker)"
    elif command -v python3 >/dev/null 2>&1; then
      age="$(python3 -c 'import sys, datetime
d = datetime.date.fromisoformat(sys.argv[1])
print((datetime.date.today() - d).days)' "$snap" 2>/dev/null || true)"
      if [ -n "${age:-}" ] && [ "$age" -gt 14 ] 2>/dev/null; then
        note "WARN: tracker snapshot is ${age} days old ($snap) and no newer committed edit was found — refresh it (/tracker)"
      else
        note "fresh enough ($snap)"
      fi
    else
      note "snapshot dated $snap with no newer committed edit (install python3 for age check)"
    fi
  fi
else
  note "no docs/tracker.md (skipped)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "OK — hub looks clean."
else
  echo "FAIL — fix the items above." >&2
fi
exit "$fail"
