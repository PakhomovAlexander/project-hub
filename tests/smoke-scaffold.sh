#!/usr/bin/env bash
# smoke-scaffold.sh — scaffold a hub from template/ the way SETUP.md prescribes,
# then require the verifier to pass on it (and to FAIL on a planted defect).
#
# This is the end-to-end guard for the template: it catches placeholder tokens the
# runbook forgot to list, links that break once repos/ is absent, non-portable
# verifier code, and a verifier that "passes" vacuously.
#
# Run from the template repo root:  tests/smoke-scaffold.sh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
HUB="$WORK/acme-hub"

# --- 1. copy the skeleton (cp -a: keeps dotfiles + the .claude/skills symlink) -------
mkdir -p "$HUB"
cp -a "$ROOT/template/." "$HUB/"
[ -L "$HUB/.claude/skills" ] || { echo "FAIL: .claude/skills symlink lost in copy" >&2; exit 1; }

# --- 2. resolve the SETUP.md §6 tokens (perl -pi: portable across GNU/BSD) ----------
TODAY="$(date +%Y-%m-%d)"
find "$HUB" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.json' \
    -o -name '*.manifest' -o -name 'Makefile' \) -print0 \
  | xargs -0 perl -pi -e "
      s/\\{\\{PROJECT_NAME\\}\\}/acme/g;
      s/\\{\\{PROJECT_TAGLINE\\}\\}/A demo app/g;
      s/\\{\\{ORG\\}\\}/acme-inc/g;
      s|\\{\\{CLONE_WORKSPACE\\}\\}|../acme-ws|g;
      s|\\{\\{HUB_REPO\\}\\}|acme-inc/hub|g;
      s/\\{\\{DEFAULT_OWNER\\}\\}/octocat/g;
      s/\\{\\{TODAY\\}\\}/$TODAY/g;
    "

# --- 3. play the agent: fill inline placeholders, drop guidance comments -------------
# multi-line <!-- TEMPLATE: … --> blocks in .md (the _template.md scaffolds keep theirs)
find "$HUB" -type f -name '*.md' -not -name '_template.md' -print0 \
  | xargs -0 perl -0pi -e 's/<!--\s*TEMPLATE:.*?-->\n?//gs'
# "# TEMPLATE…" comment lines in scripts + the manifest
find "$HUB" -type f \( -name '*.sh' -o -name '*.manifest' \) -print0 \
  | xargs -0 perl -ni -e 'print unless /^#\s*TEMPLATE/'
# remaining {{inline placeholders}} become plain filler text (-0: they span lines)
find "$HUB" -type f \( \( -name '*.md' -a -not -name '_template.md' \) \
    -o -name '*.manifest' \) -print0 \
  | xargs -0 perl -0pi -e 's/\{\{[^}]*\}\}/X/gs'

# --- 4. wire up like SETUP.md §5 ------------------------------------------------------
chmod +x "$HUB"/.claude/hooks/*.sh "$HUB"/scripts/*.sh

# --- 5. the verifier must PASS on a clean scaffold ------------------------------------
echo "== verify clean scaffold (wrapper) =="
"$ROOT/scripts/verify-hub.sh" "$HUB"
echo "== verify clean scaffold (hub-local, sh -euo off-path) =="
bash "$HUB/scripts/verify.sh" "$HUB"

# --- 6. …and must FAIL on planted defects (no vacuous passes) -------------------------
BAD="$WORK/bad-hub"
cp -a "$HUB" "$BAD"
printf '\nSee [missing doc](docs/nope.md) and {{LEFTOVER}}.\n' >> "$BAD/README.md"
printf '\nBad habit: [link into repos](../repos/acme/README.md).\n' >> "$BAD/docs/plan.md"
chmod -x "$BAD/scripts/verify.sh"
echo "== verify planted defects (must fail) =="
if bash "$BAD/scripts/verify.sh" "$BAD" > "$WORK/bad.out" 2>&1; then
  echo "FAIL: verifier passed a hub with planted defects" >&2
  cat "$WORK/bad.out" >&2
  exit 1
fi
grep -q 'LEFTOVER'            "$WORK/bad.out" || { echo "FAIL: leftover token not flagged" >&2; exit 1; }
grep -q 'broken link'         "$WORK/bad.out" || { echo "FAIL: broken link not flagged" >&2; exit 1; }
grep -q 'links into repos/'   "$WORK/bad.out" || { echo "FAIL: repos/ link not flagged" >&2; exit 1; }
grep -q 'NOT EXECUTABLE'      "$WORK/bad.out" || { echo "FAIL: exec bit not flagged" >&2; exit 1; }

echo
echo "OK — scaffold verifies clean, and the verifier catches planted defects."
