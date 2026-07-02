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
# shellcheck source=/dev/null
. "$ROOT/tests/lib.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
HUB="$WORK/acme-hub"

# --- 1. scaffold per SETUP.md §3–§5 (shared with smoke-update.sh: tests/lib.sh) -------
scaffold_hub "$ROOT" "$HUB" "https://github.com/acme-inc/project-hub" "abc1234"

# --- 2. the verifier must PASS on a clean scaffold ------------------------------------
echo "== verify clean scaffold (wrapper) =="
"$ROOT/scripts/verify-hub.sh" "$HUB"
echo "== verify clean scaffold (hub-local, sh -euo off-path) =="
bash "$HUB/scripts/verify.sh" "$HUB"

# --- 3. …and must FAIL on planted defects (no vacuous passes) -------------------------
BAD="$WORK/bad-hub"
cp -a "$HUB" "$BAD"
printf '\nSee [missing doc](docs/nope.md) and {{LEFTOVER}}.\n' >> "$BAD/README.md"
printf '\nBad habit: [link into repos](../repos/acme/README.md).\n' >> "$BAD/docs/plan.md"
chmod -x "$BAD/scripts/verify.sh"
rm "$BAD/.hub-meta.yml"
echo "== verify planted defects (must fail) =="
if bash "$BAD/scripts/verify.sh" "$BAD" > "$WORK/bad.out" 2>&1; then
  echo "FAIL: verifier passed a hub with planted defects" >&2
  cat "$WORK/bad.out" >&2
  exit 1
fi
grep -q 'LEFTOVER'                "$WORK/bad.out" || { echo "FAIL: leftover token not flagged" >&2; exit 1; }
grep -q 'broken link'             "$WORK/bad.out" || { echo "FAIL: broken link not flagged" >&2; exit 1; }
grep -q 'links into repos/'       "$WORK/bad.out" || { echo "FAIL: repos/ link not flagged" >&2; exit 1; }
grep -q 'NOT EXECUTABLE'          "$WORK/bad.out" || { echo "FAIL: exec bit not flagged" >&2; exit 1; }
grep -q 'MISSING: .hub-meta.yml'  "$WORK/bad.out" || { echo "FAIL: missing provenance not flagged" >&2; exit 1; }

echo
echo "OK — scaffold verifies clean, and the verifier catches planted defects."
