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
command -v node >/dev/null 2>&1 \
  || { echo "FAIL: node is required for workflow smoke-test coverage" >&2; exit 2; }

# --- 1. scaffold per SETUP.md §3–§5 (shared with smoke-update.sh: tests/lib.sh) -------
scaffold_hub "$ROOT" "$HUB" "https://github.com/acme-inc/project-hub" "abc1234"

# Ship one harmless workflow smoke test. The template-level wrapper must inspect
# without running it; the hub-local verifier must execute it.
mkdir -p "$HUB/tests"
cat > "$HUB/tests/smoke-proof.mjs" <<'EOF'
import { writeFileSync } from 'node:fs'
writeFileSync('.smoke-ran', 'yes\n')
EOF

# --- 2. the verifier must PASS on a clean scaffold ------------------------------------
echo "== verify clean scaffold (wrapper) =="
"$ROOT/scripts/verify-hub.sh" "$HUB"
[ ! -e "$HUB/.smoke-ran" ] \
  || { echo "FAIL: template wrapper executed code from an external hub" >&2; exit 1; }
echo "== verify clean scaffold (hub-local, sh -euo off-path) =="
bash "$HUB/scripts/verify.sh" "$HUB"
[ -f "$HUB/.smoke-ran" ] \
  || { echo "FAIL: hub-local verifier did not execute smoke-proof.mjs" >&2; exit 1; }
grep -q 'workflow-tests:' "$HUB/.github/workflows/docs-ci.yml" \
  || { echo "FAIL: generated docs CI has no workflow smoke job" >&2; exit 1; }
grep -q '"tests/\*\*"' "$HUB/.github/workflows/docs-ci.yml" \
  || { echo "FAIL: workflow test changes do not trigger generated docs CI" >&2; exit 1; }

# A hub with smoke tests must not report success when their runtime is absent.
NO_NODE_BIN="$WORK/no-node-bin"
mkdir -p "$NO_NODE_BIN"
for tool in basename dirname find git grep head sed sort; do
  ln -s "$(command -v "$tool")" "$NO_NODE_BIN/$tool"
done
set +e
PATH="$NO_NODE_BIN" /bin/bash "$HUB/scripts/verify.sh" "$HUB" \
  > "$WORK/no-node.out" 2>&1
no_node_rc=$?
set -e
[ "$no_node_rc" -ne 0 ] \
  || { echo "FAIL: verifier passed without Node while smoke tests exist" >&2; exit 1; }
grep -q 'workflow smoke tests exist but node is unavailable' "$WORK/no-node.out" \
  || { echo "FAIL: missing-Node diagnostic was not reported" >&2; exit 1; }

# A committed tracker edit newer than its declared snapshot must warn but not fail.
STALE="$WORK/stale-hub"
cp -a "$HUB" "$STALE"
perl -pi -e 's/\*\*Snapshot:\*\* [0-9-]+/**Snapshot:** 2000-01-01/' \
  "$STALE/docs/tracker.md"
git -C "$STALE" init -q
git -C "$STALE" config user.name smoke
git -C "$STALE" config user.email smoke@example.invalid
git -C "$STALE" add -A
GIT_AUTHOR_DATE='2000-01-02T12:00:00Z' GIT_COMMITTER_DATE='2000-01-02T12:00:00Z' \
  git -C "$STALE" commit -qm 'tracker edited without snapshot bump'
bash "$STALE/scripts/verify.sh" "$STALE" > "$WORK/stale.out"
grep -q 'tracker edited 2000-01-02 but its Snapshot line still says 2000-01-01' \
  "$WORK/stale.out" \
  || { echo "FAIL: newer committed tracker edit was not reported" >&2; exit 1; }
PATH="$NO_NODE_BIN" /bin/bash "$STALE/scripts/verify.sh" "$STALE" \
  > "$WORK/stale-no-python.out" 2>&1 || true
grep -q 'tracker edited 2000-01-02 but its Snapshot line still says 2000-01-01' \
  "$WORK/stale-no-python.out" \
  || { echo "FAIL: committed tracker edit needs no Python to be reported" >&2; exit 1; }

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

# --- 4. each defect must fail the run ON ITS OWN --------------------------------------
# The combined hub above proves each defect is REPORTED, but its single "exits
# nonzero" assertion is over-determined: any one of the five satisfies it. So a
# check could keep printing its message while losing its `fail=1` wire and both
# this suite and smoke-update would stay green — while verify.sh greenlit a real
# hub whose only defect was, say, a broken link. Plant them one at a time.
echo "== verify each defect in isolation (must fail on its own) =="
ONE="$WORK/one-hub"
fresh() { rm -rf "$ONE"; cp -a "$HUB" "$ONE"; }   # a clean hub, one defect at a time
must_fail() {
  if bash "$ONE/scripts/verify.sh" "$ONE" > "$WORK/one.out" 2>&1; then
    echo "FAIL: verify.sh passed a hub whose only defect was: $1" >&2
    cat "$WORK/one.out" >&2
    exit 1
  fi
  echo "  ✓ $1 fails on its own"
}
fresh; printf '\n{{LEFTOVER}}\n' >> "$ONE/README.md"                 ; must_fail "a leftover token"
fresh; printf '\n[missing](docs/nope.md)\n' >> "$ONE/README.md"      ; must_fail "a broken link"
fresh; printf '\n[r](../repos/acme/README.md)\n' >> "$ONE/docs/plan.md"; must_fail "a link into repos/"
fresh; chmod -x "$ONE/scripts/verify.sh"                             ; must_fail "a non-exec script"
fresh; find "$ONE/.agents/skills" -name '*.sh' -exec chmod -x {} +   ; must_fail "a non-exec skill script"
fresh; find "$ONE/tools" -name '*.sh' -exec chmod -x {} +            ; must_fail "a non-exec tools script"
fresh; rm "$ONE/.hub-meta.yml"                                       ; must_fail "missing provenance"
fresh; printf 'throw new Error("failing assertion: planted")\n' \
  > "$ONE/tests/smoke-planted.mjs"                                   ; must_fail "a failing workflow smoke test"

echo
echo "OK — scaffold verifies clean, and every planted defect fails on its own."
