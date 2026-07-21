#!/usr/bin/env bash
# smoke-srh.sh — behavioral test for the self-review-heavy skill's scripts:
# the ledger lifecycle (fingerprint dedup, resolve, the three convergence exit
# codes), bundle.sh on a scratch repo, and checks.sh pass/fail recording.
# Offline; requires git + jq (like the skill itself).
#
# Run from the template repo root:  tests/smoke-srh.sh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRH="$ROOT/template/.agents/skills/self-review-heavy/scripts"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TAB="$(printf '\t')"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# --- ledger lifecycle -----------------------------------------------------
D="$WORK/ledger"
"$SRH/ledger.sh" init "$D" >/dev/null

cat > "$WORK/f1.json" <<'EOF'
{"verdict":"request-changes","findings":[
 {"severity":"major","file":"src/a.cpp","line":1,"title":"Major issue A","body":"x","confidence":0.9},
 {"severity":"minor","file":"src/b.h","title":"Minor issue B","body":"y","confidence":0.8}]}
EOF

out="$("$SRH/ledger.sh" add "$D" --source deep "$WORK/f1.json")"
[ "$out" = "new=2 dup=0 open=2" ] || fail "first add: got '$out'"
out="$("$SRH/ledger.sh" add "$D" --source cross "$WORK/f1.json")"
[ "$out" = "new=0 dup=2 open=2" ] || fail "duplicate add: got '$out'"
pass "ledger add dedups by fingerprint"

rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "open major must not converge (rc=$rc)"

fp="$("$SRH/ledger.sh" list "$D" --status open | jq -r 'select(.severity=="major").fp')"
"$SRH/ledger.sh" resolve "$D" "$fp" fixed --note test >/dev/null
"$SRH/ledger.sh" bump "$D" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "fixed major + minor below gate must converge (rc=$rc)"
pass "convergence: open major blocks, minor under the gate doesn't"

fp2="$("$SRH/ledger.sh" list "$D" --status open | jq -r .fp)"
"$SRH/ledger.sh" resolve "$D" "$fp2" contested >/dev/null
rc=0; "$SRH/ledger.sh" converged "$D" --gate minor >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "contested must block at its severity (rc=$rc)"
pass "contested blocks convergence"

"$SRH/ledger.sh" bump "$D" >/dev/null   # round 3
rc=0; "$SRH/ledger.sh" converged "$D" --gate minor --max-rounds 3 >/dev/null || rc=$?
[ "$rc" -eq 3 ] || fail "round cap must exit 3 (rc=$rc)"
pass "max-rounds exhaustion exits 3"

report="$("$SRH/ledger.sh" report "$D")"
case "$report" in *"Major issue A"*) ;; *) fail "report misses a finding" ;; esac
pass "report renders the ledger"

# --- bundle.sh on a scratch repo ------------------------------------------
R="$WORK/repo"
git init -q -b main "$R"
(
  cd "$R"
  git config user.email srh@test && git config user.name srh
  mkdir -p src tests
  echo a > src/MergeWidget.cpp
  echo t > tests/merge_widget_test.sh
  git add -A && git commit -qm base
  git switch -qc feature
  echo b >> src/MergeWidget.cpp && git commit -qam change
)
B="$("$SRH/bundle.sh" -C "$R" --base main --out "$WORK/bundle" | tail -1)"
[ -s "$B/diff.patch" ] || fail "bundle: empty diff.patch"
grep -q 'src/MergeWidget.cpp' "$B/files.txt" || fail "bundle: files.txt misses the change"
grep -q 'tests/merge_widget_test.sh' "$B/tests_candidates.txt" \
  || fail "bundle: name-token match missed the test candidate"
grep -q 'merge_base=' "$B/meta.env" || fail "bundle: meta.env incomplete"
pass "bundle.sh builds a bundle with diff, files, and test candidates"

# --- checks.sh records pass/fail -------------------------------------------
printf 'good\ttrue\nbad\tfalse\n' > "$WORK/checks.tsv"
rc=0; "$SRH/checks.sh" --file "$WORK/checks.tsv" --out "$WORK/cb" -C "$WORK" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "checks.sh must exit 1 when a check fails (rc=$rc)"
grep -q "good${TAB}pass" "$WORK/cb/checks.tsv" || fail "checks.tsv missing the pass row"
grep -q "bad${TAB}fail" "$WORK/cb/checks.tsv" || fail "checks.tsv missing the fail row"
pass "checks.sh records pass/fail and exits non-zero on failure"

echo "smoke-srh: all good"
