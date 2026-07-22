#!/usr/bin/env bash
# smoke-srh.sh — behavioral test for the self-review-heavy skill's scripts:
# the ledger lifecycle (fingerprint dedup, reopen-on-re-report — which counts
# as convergence news — resolve, the three convergence exit codes, schema
# validation and empty-field handling on add), bundle.sh on scratch repos
# (test-only diffs, untracked files incl. non-ASCII names, dangling
# origin/HEAD fallback), and checks.sh recording (trailing newline, re-run
# truncation, input/output collision, vacuous runs).
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
[ "$out" = "new=2 dup=0 reopened=0 escalated=0 open=2" ] || fail "first add: got '$out'"
out="$("$SRH/ledger.sh" add "$D" --source cross "$WORK/f1.json")"
[ "$out" = "new=0 dup=2 reopened=0 escalated=0 open=2" ] || fail "duplicate add: got '$out'"
pass "ledger add dedups by fingerprint"

cat > "$WORK/bad.json" <<'EOF'
{"findings":[{"severity":"critical","file":"src/a.cpp","title":"Out-of-enum severity","body":"z"}]}
EOF
rc=0; "$SRH/ledger.sh" add "$D" --source deep "$WORK/bad.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "malformed severity must be rejected (rc=$rc)"
pass "ledger add rejects schema-invalid findings"

# Empty file → "(change-wide)" sentinel; empty AND whitespace-only titles →
# skipped with a warning; the rest of the batch still lands (one bad entry
# must not sink nine good ones).
cat > "$WORK/edge.json" <<'EOF'
{"findings":[
 {"severity":"minor","file":"","title":"Change-wide concern","body":"b"},
 {"severity":"minor","file":"x.c","title":"","body":"b"},
 {"severity":"minor","file":"w.c","title":"   ","body":"b"},
 {"severity":"minor","file":"y.c","title":"Normal finding","body":"b"}]}
EOF
"$SRH/ledger.sh" init "$WORK/led-edge" >/dev/null
out="$("$SRH/ledger.sh" add "$WORK/led-edge" --source cross "$WORK/edge.json" 2>/dev/null)"
[ "$out" = "new=2 dup=0 reopened=0 escalated=0 open=2" ] || fail "edge add: got '$out'"
"$SRH/ledger.sh" list "$WORK/led-edge" | jq -r .file | grep -q '(change-wide)' \
  || fail "empty file did not become the (change-wide) sentinel"
pass "ledger add handles empty file/title per finding, not wholesale"

# Fingerprints: case/whitespace variants of a title are one finding, but
# punctuation and non-ASCII are significant — "x < 0" vs "x > 0" and two
# different Cyrillic titles must NOT collapse into one entry.
cat > "$WORK/fpx.json" <<'EOF'
{"findings":[
 {"severity":"minor","file":"a.c","title":"Reject x < 0","body":"b"},
 {"severity":"blocker","file":"a.c","title":"Reject x > 0","body":"b"},
 {"severity":"major","file":"a.c","title":"Ошибка чтения","body":"b"},
 {"severity":"major","file":"a.c","title":"Утечка памяти","body":"b"}]}
EOF
"$SRH/ledger.sh" init "$WORK/led-fp" >/dev/null
out="$("$SRH/ledger.sh" add "$WORK/led-fp" --source deep "$WORK/fpx.json")"
[ "$out" = "new=4 dup=0 reopened=0 escalated=0 open=4" ] || fail "fingerprint collapsed distinct titles: '$out'"
cat > "$WORK/fpy.json" <<'EOF'
{"findings":[{"severity":"minor","file":"a.c","title":"reject   X < 0","body":"b"}]}
EOF
out="$("$SRH/ledger.sh" add "$WORK/led-fp" --source cross "$WORK/fpy.json")"
[ "$out" = "new=0 dup=1 reopened=0 escalated=0 open=4" ] || fail "case/whitespace variant did not dedup: '$out'"
pass "fingerprints keep punctuation/non-ASCII distinct, fold case/whitespace"

rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "open major must not converge (rc=$rc)"

fp="$("$SRH/ledger.sh" list "$D" --status open | jq -r 'select(.severity=="major").fp')"
"$SRH/ledger.sh" resolve "$D" "$fp" fixed --note test >/dev/null
"$SRH/ledger.sh" bump "$D" >/dev/null   # round 2
rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "fixed major + minor below gate must converge (rc=$rc)"
pass "convergence: open major blocks, minor under the gate doesn't"

# A later-round re-report of a resolved finding must reopen it AND count as
# news: even after an immediate re-fix, the round is not clean — otherwise a
# failed fix's second attempt ships with zero reviewer eyes on it.
out="$("$SRH/ledger.sh" add "$D" --source deep "$WORK/f1.json" | tail -1)"
[ "$out" = "new=0 dup=1 reopened=1 escalated=0 open=2" ] || fail "re-report: got '$out'"
rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "reopened major must block convergence (rc=$rc)"
"$SRH/ledger.sh" resolve "$D" "$fp" fixed --note "re-fix" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "re-fixed reopen must still not converge in the same round (rc=$rc)"
"$SRH/ledger.sh" bump "$D" >/dev/null   # round 3
rc=0; "$SRH/ledger.sh" converged "$D" >/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "clean round after the re-fix must converge (rc=$rc)"
pass "re-report reopens, counts as news, and needs a clean round to converge"

# A reopen adopts the re-report's severity and evidence: a round-1 minor
# re-reported as a blocker must block on its NEW severity, not the stale one.
"$SRH/ledger.sh" init "$WORK/led-esc" >/dev/null
cat > "$WORK/esc1.json" <<'EOF'
{"findings":[{"severity":"minor","file":"c.c","title":"Escalating issue","body":"weak"}]}
EOF
cat > "$WORK/esc2.json" <<'EOF'
{"findings":[{"severity":"blocker","file":"c.c","title":"Escalating issue","body":"crash repro"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-esc" --source deep "$WORK/esc1.json" >/dev/null
efp="$(jq -r .fp "$WORK/led-esc/ledger.jsonl")"
"$SRH/ledger.sh" resolve "$WORK/led-esc" "$efp" fixed >/dev/null
"$SRH/ledger.sh" bump "$WORK/led-esc" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-esc" --source cross "$WORK/esc2.json" >/dev/null
[ "$(jq -r .severity "$WORK/led-esc/ledger.jsonl")" = "blocker" ] \
  || fail "reopen kept the stale severity"
rc=0; "$SRH/ledger.sh" converged "$WORK/led-esc" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "escalated reopen must block convergence (rc=$rc)"
pass "reopen adopts the re-report's severity and evidence"

# A still-OPEN finding re-reported at higher severity is escalated in place
# (adopt + news); a rejected/wontfix one is NEVER auto-reopened — reviewers
# only see open claims, so they'd rediscover rejected ones forever.
"$SRH/ledger.sh" init "$WORK/led-esc2" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-esc2" --source deep "$WORK/esc1.json" >/dev/null
"$SRH/ledger.sh" bump "$WORK/led-esc2" >/dev/null
out="$("$SRH/ledger.sh" add "$WORK/led-esc2" --source cross "$WORK/esc2.json" | tail -1)"
[ "$out" = "new=0 dup=0 reopened=0 escalated=1 open=1" ] || fail "open escalation: got '$out'"
[ "$(jq -r .severity "$WORK/led-esc2/ledger.jsonl")" = "blocker" ] || fail "escalation kept stale severity"
"$SRH/ledger.sh" init "$WORK/led-rej" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-rej" --source deep "$WORK/esc1.json" >/dev/null
rfp="$(jq -r .fp "$WORK/led-rej/ledger.jsonl")"
"$SRH/ledger.sh" resolve "$WORK/led-rej" "$rfp" rejected --note "not real" >/dev/null
"$SRH/ledger.sh" bump "$WORK/led-rej" >/dev/null
out="$("$SRH/ledger.sh" add "$WORK/led-rej" --source cross "$WORK/esc2.json" 2>/dev/null | tail -1)"
[ "$out" = "new=0 dup=1 reopened=0 escalated=0 open=0" ] || fail "rejected re-report: got '$out'"
[ "$(jq -r .status "$WORK/led-rej/ledger.jsonl")" = "rejected" ] \
  || fail "rejected re-report must not change the status"
# The higher-severity evidence is adopted in place AND counts as news for
# one round (bounded — severity is monotone): an accepted fix of the
# escalated claim must survive a clean round, and a manual re-triage to
# contested inherits the REAL rank.
[ "$(jq -r .severity "$WORK/led-rej/ledger.jsonl")" = "blocker" ] \
  || fail "rejected re-report did not adopt the higher severity"
rc=0; "$SRH/ledger.sh" converged "$WORK/led-rej" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "escalated adoption must count as news this round (rc=$rc)"
"$SRH/ledger.sh" bump "$WORK/led-rej" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-rej" >/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "still-rejected escalation must stop blocking after one clean round (rc=$rc)"
"$SRH/ledger.sh" resolve "$WORK/led-rej" "$rfp" contested >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-rej" >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "manually contested escalated re-report must block (rc=$rc)"
pass "open findings escalate in place; rejected ones adopt evidence + news, never auto-reopen"

# Adoption must not be once-per-round: stages ingest separately, and the
# SECOND same-round re-report may be the one carrying blocker evidence.
"$SRH/ledger.sh" init "$WORK/led-rej2" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-rej2" --source deep "$WORK/esc1.json" >/dev/null
r2fp="$(jq -r .fp "$WORK/led-rej2/ledger.jsonl")"
"$SRH/ledger.sh" resolve "$WORK/led-rej2" "$r2fp" rejected >/dev/null
"$SRH/ledger.sh" bump "$WORK/led-rej2" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-rej2" --source deep "$WORK/esc1.json" >/dev/null 2>&1
"$SRH/ledger.sh" add "$WORK/led-rej2" --source cross "$WORK/esc2.json" >/dev/null 2>&1
[ "$(jq -r .severity "$WORK/led-rej2/ledger.jsonl")" = "blocker" ] \
  || fail "same-round second re-report did not adopt the higher severity"
pass "rejected-escalation adoption works on any re-report, not once per round"

fp2="$("$SRH/ledger.sh" list "$D" --status open | jq -r .fp)"
"$SRH/ledger.sh" resolve "$D" "$fp2" contested >/dev/null
rc=0; "$SRH/ledger.sh" converged "$D" --gate minor --max-rounds 6 >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "contested must block at its severity (rc=$rc)"
pass "contested blocks convergence"

"$SRH/ledger.sh" bump "$D" >/dev/null   # round 4
rc=0; "$SRH/ledger.sh" converged "$D" --gate minor --max-rounds 4 >/dev/null || rc=$?
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

# --uncommitted must carry untracked file CONTENTS into the reviewed diff —
# including non-ASCII names, which ls-files C-quotes on its text output.
(
  cd "$R"
  printf 'brand new logic\n' > src/NewThing.cpp
  printf 'unicode content here\n' > "src/тест.cpp"
)
B3="$("$SRH/bundle.sh" -C "$R" --base main --uncommitted --out "$WORK/bundle3" | tail -1)"
grep -q 'src/NewThing.cpp' "$B3/files.txt" || fail "bundle: untracked file missing from files.txt"
grep -q 'brand new logic' "$B3/diff.patch" || fail "bundle: untracked content missing from diff.patch"
grep -q 'unicode content here' "$B3/diff.patch" || fail "bundle: non-ASCII untracked content missing"
pass "bundle.sh includes untracked contents (incl. non-ASCII names) under --uncommitted"

# --out INSIDE the worktree must not bundle its own artifacts: the untracked
# scan excludes OUT, while other untracked files still ride along.
B5="$("$SRH/bundle.sh" -C "$R" --base main --uncommitted --out "$R/innerbundle" | tail -1)"
grep -q 'innerbundle' "$B5/files.txt" && fail "bundle: reviewed its own artifacts under --out inside the worktree"
grep -q 'src/NewThing.cpp' "$B5/files.txt" || fail "bundle: OUT exclusion dropped a real untracked file"
pass "bundle.sh excludes an in-worktree --out dir from the reviewed diff"

# --out at the worktree root cannot be excluded via pathspec — refuse it;
# and a glob-named OUT must not over-exclude sibling untracked files: with a
# plain :(exclude) the pathspec 'o*' would swallow oX/ too — only
# :(exclude,literal) keeps the sibling. This pin fails if ,literal is dropped.
rc=0; "$SRH/bundle.sh" -C "$R" --base main --uncommitted --out "$R" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "bundle: --out at the worktree root must be refused (rc=$rc)"
[ ! -e "$R/diff.patch" ] || fail "bundle: refused root --out still littered artifacts"
rc=0; "$SRH/bundle.sh" -C "$R" --base main --out "$R" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "bundle: root --out must be refused in committed mode too (rc=$rc)"
mkdir -p "$R/oX"; printf 'sibling\n' > "$R/oX/sibling.txt"
B6="$("$SRH/bundle.sh" -C "$R" --base main --uncommitted --out "$R/o*" | tail -1)"
grep -q 'oX/sibling.txt' "$B6/files.txt" \
  || fail "bundle: exclusion over-matched a glob sibling (o* vs oX) — ,literal regressed"
pass "bundle.sh refuses a worktree-root --out and keeps the exclusion literal"

# Auto base detection must survive a dangling origin/HEAD (post-migration
# fetch --prune state) by falling back to a verified candidate.
R2="$WORK/repo2"
git init -q -b main "$R2"
(
  cd "$R2"
  git config user.email srh@test && git config user.name srh
  echo a > f && git add -A && git commit -qm base
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master   # dangling
  git switch -qc feature && echo b >> f && git commit -qam change
)
B4="$("$SRH/bundle.sh" -C "$R2" --out "$WORK/bundle4" | tail -1)"
grep -q 'base=origin/main' "$B4/meta.env" || fail "bundle: dangling origin/HEAD not survived"
pass "bundle.sh falls back past a dangling origin/HEAD"

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

# --file <out>/checks.tsv would truncate its own input — must be refused,
# and a run that executed zero checks must never read as green.
mkdir -p "$WORK/cb4"; printf 'lint\tfalse\n' > "$WORK/cb4/checks.tsv"
rc=0; "$SRH/checks.sh" --file "$WORK/cb4/checks.tsv" --out "$WORK/cb4" -C "$WORK" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "input/output collision must be refused (rc=$rc)"
printf '# comments only\n' > "$WORK/c3.tsv"
rc=0; "$SRH/checks.sh" --file "$WORK/c3.tsv" --out "$WORK/cb5" -C "$WORK" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "vacuous run must exit non-zero (rc=$rc)"
pass "checks.sh refuses self-truncation and vacuous green runs"

echo "smoke-srh: all good"
