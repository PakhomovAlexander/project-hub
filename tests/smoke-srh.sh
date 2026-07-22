#!/usr/bin/env bash
# smoke-srh.sh — behavioral test for the self-review-heavy skill's scripts:
# the ledger lifecycle (fingerprint dedup, reopen-on-re-report, resolve, the
# three convergence exit codes, schema validation on add), bundle.sh on a
# scratch repo (incl. test-only diffs and untracked files), and checks.sh
# pass/fail recording (incl. trailing-newline and re-run truncation).
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
[ "$out" = "new=2 dup=0 reopened=0 open=2" ] || fail "first add: got '$out'"
out="$("$SRH/ledger.sh" add "$D" --source cross "$WORK/f1.json")"
[ "$out" = "new=0 dup=2 reopened=0 open=2" ] || fail "duplicate add: got '$out'"
pass "ledger add dedups by fingerprint"

cat > "$WORK/bad.json" <<'EOF'
{"findings":[{"severity":"critical","file":"src/a.cpp","title":"Out-of-enum severity","body":"z"}]}
EOF
rc=0; "$SRH/ledger.sh" add "$D" --source deep "$WORK/bad.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "malformed severity must be rejected (rc=$rc)"
pass "ledger add rejects schema-invalid findings"

rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "open major must not converge (rc=$rc)"

fp="$("$SRH/ledger.sh" list "$D" --status open | jq -r 'select(.severity=="major").fp')"
"$SRH/ledger.sh" resolve "$D" "$fp" fixed --note test >/dev/null
"$SRH/ledger.sh" bump "$D" >/dev/null   # round 2
rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "fixed major + minor below gate must converge (rc=$rc)"
pass "convergence: open major blocks, minor under the gate doesn't"

# A later-round re-report of a resolved finding must reopen it, not vanish
# as a duplicate — otherwise a failed fix converges silently.
out="$("$SRH/ledger.sh" add "$D" --source deep "$WORK/f1.json" | tail -1)"
[ "$out" = "new=0 dup=1 reopened=1 open=2" ] || fail "re-report: got '$out'"
rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "reopened major must block convergence (rc=$rc)"
pass "re-report of a fixed finding reopens it and blocks convergence"

"$SRH/ledger.sh" resolve "$D" "$fp" fixed --note "fixed for real" >/dev/null
fp2="$("$SRH/ledger.sh" list "$D" --status open | jq -r .fp)"
"$SRH/ledger.sh" resolve "$D" "$fp2" contested >/dev/null
rc=0; "$SRH/ledger.sh" converged "$D" --gate minor --max-rounds 5 >/dev/null || rc=$?
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
grep -q 'changed_lines=' "$B/meta.env" || fail "bundle: meta.env lacks changed_lines"
pass "bundle.sh builds a bundle with diff, files, and test candidates"

# A test-only diff must still produce a complete bundle (the token pipeline
# has no non-test paths to chew on — that used to kill the script).
(
  cd "$R"
  git switch -qc tests-only main
  echo more >> tests/merge_widget_test.sh && git commit -qam tests
)
B2="$("$SRH/bundle.sh" -C "$R" --base main --out "$WORK/bundle2" | tail -1)"
[ -s "$B2/meta.env" ] || fail "bundle: test-only diff lost meta.env"
[ "$B2" = "$WORK/bundle2" ] || fail "bundle: test-only diff broke the stdout contract"
pass "bundle.sh survives a test-only diff"

# --uncommitted must carry untracked file CONTENTS into the reviewed diff.
(
  cd "$R"
  printf 'brand new logic\n' > src/NewThing.cpp
)
B3="$("$SRH/bundle.sh" -C "$R" --base main --uncommitted --out "$WORK/bundle3" | tail -1)"
grep -q 'src/NewThing.cpp' "$B3/files.txt" || fail "bundle: untracked file missing from files.txt"
grep -q 'brand new logic' "$B3/diff.patch" || fail "bundle: untracked content missing from diff.patch"
pass "bundle.sh includes untracked contents under --uncommitted"

# --- checks.sh records pass/fail -------------------------------------------
printf 'good\ttrue\nbad\tfalse\n' > "$WORK/checks.tsv"
rc=0; "$SRH/checks.sh" --file "$WORK/checks.tsv" --out "$WORK/cb" -C "$WORK" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "checks.sh must exit 1 when a check fails (rc=$rc)"
grep -q "good${TAB}pass" "$WORK/cb/checks.tsv" || fail "checks.tsv missing the pass row"
grep -q "bad${TAB}fail" "$WORK/cb/checks.tsv" || fail "checks.tsv missing the fail row"
pass "checks.sh records pass/fail and exits non-zero on failure"

# The final line of a TSV without a trailing newline must still run.
printf 'first\ttrue\nlast\ttrue' > "$WORK/checks2.tsv"
"$SRH/checks.sh" --file "$WORK/checks2.tsv" --out "$WORK/cb2" -C "$WORK" >/dev/null
grep -q "last${TAB}pass" "$WORK/cb2/checks.tsv" || fail "checks.sh dropped the unterminated last line"
pass "checks.sh runs the last check without a trailing newline"

# A re-run must truncate checks.tsv — stale fail rows must not survive.
printf 'build\tfalse\n' > "$WORK/c1.tsv"
printf 'build\ttrue\n'  > "$WORK/c2.tsv"
"$SRH/checks.sh" --file "$WORK/c1.tsv" --out "$WORK/cb3" -C "$WORK" >/dev/null 2>&1 || true
"$SRH/checks.sh" --file "$WORK/c2.tsv" --out "$WORK/cb3" -C "$WORK" >/dev/null
[ "$(wc -l < "$WORK/cb3/checks.tsv" | tr -d ' ')" = "1" ] || fail "checks.tsv kept stale rows"
grep -q "build${TAB}pass" "$WORK/cb3/checks.tsv" || fail "checks.tsv lost the current row"
pass "checks.sh re-run reflects only the latest results"

echo "smoke-srh: all good"
