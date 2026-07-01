#!/usr/bin/env bash
# verify-hub.sh — sanity-check a GENERATED Project Hub before calling setup done.
#
# This is the executable form of SETUP.md §7's "grep the result before you finish".
# Run it against the hub you just scaffolded (NOT this template repo):
#
#   scripts/verify-hub.sh ../my-project-hub
#   scripts/verify-hub.sh            # defaults to the current directory
#
# Checks:
#   1. No leftover {{TOKEN}} placeholders    (ignoring *_template.md, which keep them)
#   2. No leftover <!-- TEMPLATE: … --> notes (same exception)
#   3. The risky-commands hook exists and is executable
#   4. Relative markdown links resolve to a real file
#
# Exits non-zero if any check fails, printing each offending file:line.
set -u

HUB="${1:-.}"
if [ ! -d "$HUB" ]; then
  echo "not a directory: $HUB" >&2
  exit 2
fi
HUB="$(cd -- "$HUB" >/dev/null 2>&1 && pwd)"

fail=0
note() { printf '  %s\n' "$1"; }

# Markdown files to link-check, excluding the template's own *_template.md scaffolds
# (those legitimately still contain {{ }} placeholders and TEMPLATE: markers).
mapfile -t MD < <(find "$HUB" -type f -name '*.md' \
  -not -path '*/.git/*' -not -name '_template.md' | sort)

# 1 + 2: leftover placeholders / template comments -----------------------------------
echo "==> leftover placeholders / TEMPLATE markers"
hits="$(grep -rnE '\{\{|TEMPLATE:' "$HUB" \
  --include='*.md' --include='*.sh' --include='*.json' 2>/dev/null \
  | grep -v '/_template\.md:' || true)"
if [ -n "$hits" ]; then
  fail=1
  while IFS= read -r l; do note "$l"; done <<<"$hits"
else
  note "clean"
fi

# 3: hook present + executable -------------------------------------------------------
echo "==> risky-commands hook"
hook="$HUB/.claude/hooks/ask-before-risky-commands.sh"
if [ ! -f "$hook" ]; then
  note "MISSING: $hook"; fail=1
elif [ ! -x "$hook" ]; then
  note "NOT EXECUTABLE: chmod +x .claude/hooks/ask-before-risky-commands.sh"; fail=1
else
  note "present and executable"
fi

# 3b: any shipped shell scripts are executable ---------------------------------------
# scripts/repos.sh is dropped for single-repo hubs; scripts/worktree.sh is kept — so
# check whatever is present rather than requiring a fixed set.
echo "==> scripts executable"
scriptbad=0
while IFS= read -r s; do
  [ -x "$s" ] || { note "NOT EXECUTABLE: chmod +x ${s#$HUB/}"; scriptbad=1; }
done < <(find "$HUB/scripts" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | sort)
[ "$scriptbad" -eq 0 ] && note "all executable (or none present)" || fail=1

# 4: relative markdown links resolve -------------------------------------------------
echo "==> internal markdown links"
linkbad=0
for f in "${MD[@]}"; do
  dir="$(dirname -- "$f")"
  while IFS= read -r tgt; do
    case "$tgt" in http*|mailto:*|\#*|"") continue ;; esac
    path="${tgt%%#*}"                 # strip #anchor
    [ -z "$path" ] && continue
    case "$path" in
      /*) resolved="$HUB$path" ;;     # hub-absolute (rare)
      *)  resolved="$dir/$path" ;;
    esac
    if [ ! -e "$resolved" ]; then
      note "$f → broken link: $tgt"
      linkbad=1
    fi
  done < <(grep -oE '\]\([^)#][^)]*\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done
[ "$linkbad" -eq 0 ] && note "all resolve" || fail=1

echo
if [ "$fail" -eq 0 ]; then
  echo "OK — hub looks clean."
else
  echo "FAIL — fix the items above (see SETUP.md §7)." >&2
fi
exit "$fail"
