#!/usr/bin/env bash
# smoke-srh.sh — behavioral test for the self-review-heavy skill's scripts:
# the ledger lifecycle (fingerprint dedup, reopen-on-re-report — which counts
# as convergence news, in the same round too — resolve, news accounting for
# rejected vs fixed, dispute and benchmark-demand tracking, the three
# convergence exit codes, schema validation and empty-field handling on add,
# clean errors on an uninitialized dir), bundle.sh on scratch repos (test-only
# diffs, untracked files incl. non-ASCII names, shell-metacharacter path
# detection, dangling origin/HEAD fallback), and checks.sh (placeholder
# substitution with shell-quoting, trailing newline, re-run truncation,
# input/output collision, vacuous runs).
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
{"summary":null,"benchmark_demands":[],"disputes":[],"verdict":"request-changes","findings":[
 {"severity":"major","file":"src/a.cpp","line":1,"title":"Major issue A","body":"x","confidence":0.9},
 {"severity":"minor","file":"src/b.h","title":"Minor issue B","body":"y","confidence":0.8}]}
EOF

out="$("$SRH/ledger.sh" add "$D" --source deep "$WORK/f1.json")"
[ "$out" = "new=2 dup=0 reopened=0 escalated=0 open=2" ] || fail "first add: got '$out'"
out="$("$SRH/ledger.sh" add "$D" --source cross "$WORK/f1.json")"
[ "$out" = "new=0 dup=2 reopened=0 escalated=0 open=2" ] || fail "duplicate add: got '$out'"
pass "ledger add dedups by fingerprint"

cat > "$WORK/bad.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"critical","file":"src/a.cpp","title":"Out-of-enum severity","body":"z"}]}
EOF
rc=0; "$SRH/ledger.sh" add "$D" --source deep "$WORK/bad.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "malformed severity must be rejected (rc=$rc)"
pass "ledger add rejects schema-invalid findings"

# Empty file → "(change-wide)" sentinel; empty AND whitespace-only titles →
# skipped with a warning; the rest of the batch still lands (one bad entry
# must not sink nine good ones).
cat > "$WORK/edge.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[
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
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[
 {"severity":"minor","file":"a.c","title":"Reject x < 0","body":"b"},
 {"severity":"blocker","file":"a.c","title":"Reject x > 0","body":"b"},
 {"severity":"major","file":"a.c","title":"Ошибка чтения","body":"b"},
 {"severity":"major","file":"a.c","title":"Утечка памяти","body":"b"}]}
EOF
"$SRH/ledger.sh" init "$WORK/led-fp" >/dev/null
out="$("$SRH/ledger.sh" add "$WORK/led-fp" --source deep "$WORK/fpx.json")"
[ "$out" = "new=4 dup=0 reopened=0 escalated=0 open=4" ] || fail "fingerprint collapsed distinct titles: '$out'"
cat > "$WORK/fpy.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"minor","file":"a.c","title":"reject   X < 0","body":"b"}]}
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

# The gate is re-run WITHIN a round after fixes ("fix, re-run the gate"), and
# that re-run is exactly where a fix that didn't hold surfaces — so a
# re-report of a fixed finding must reopen with no bump in between. Round-
# guarding this let a still-broken build read as zero open blockers.
"$SRH/ledger.sh" init "$WORK/led-same" >/dev/null
cat > "$WORK/gate.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"blocker","file":"build","title":"Build fails","body":"linker error"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-same" --source gate "$WORK/gate.json" >/dev/null
gfp="$(jq -r .fp "$WORK/led-same/ledger.jsonl")"
"$SRH/ledger.sh" resolve "$WORK/led-same" "$gfp" fixed --note "patched" >/dev/null
out="$("$SRH/ledger.sh" add "$WORK/led-same" --source gate "$WORK/gate.json" | tail -1)"
[ "$out" = "new=0 dup=0 reopened=1 escalated=0 open=1" ] || fail "same-round re-report: got '$out'"
rc=0; "$SRH/ledger.sh" converged "$WORK/led-same" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a fix that didn't hold must block, same round or not (rc=$rc)"
pass "a same-round gate re-run catches a fix that didn't hold"

# News accounting. A round that produced only FALSE POSITIVES added no new
# external signal, so it must not buy itself another round; a round that
# produced a FIX must, because that new code has not been reviewed yet.
cat > "$WORK/fp1.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"major","file":"a.c","title":"False alarm","body":"b"}]}
EOF
"$SRH/ledger.sh" init "$WORK/led-news" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-news" --source deep "$WORK/fp1.json" >/dev/null
"$SRH/ledger.sh" resolve "$WORK/led-news" "$(jq -r .fp "$WORK/led-news/ledger.jsonl")" \
  rejected --note "traced: guarded upstream" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-news" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "an all-false-positive round must converge (rc=$rc)"
"$SRH/ledger.sh" init "$WORK/led-news2" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-news2" --source deep "$WORK/fp1.json" >/dev/null
"$SRH/ledger.sh" resolve "$WORK/led-news2" "$(jq -r .fp "$WORK/led-news2/ledger.jsonl")" fixed >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-news2" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a fix must still cost a clean round (rc=$rc)"
pass "rejections clear convergence news; fixes keep it"

# Disputes and benchmark demands arrive with the findings and become ledger
# state — `unverified` names the claims a stage never took a position on,
# which are UNVERIFIED, not confirmed.
"$SRH/ledger.sh" init "$WORK/led-dis" >/dev/null
cat > "$WORK/deep2.json" <<'EOF'
{"verdict":"request-changes","summary":null,"disputes":[],"findings":[
 {"severity":"major","file":"a.c","title":"Claim one","body":"b"},
 {"severity":"major","file":"b.c","title":"Claim two","body":"b"}],
 "benchmark_demands":[{"claim":"the rewrite is faster","why":"hot path","suggested_method":"interleaved A/B, 7 runs"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-dis" --source deep "$WORK/deep2.json" >/dev/null
d1="$("$SRH/ledger.sh" list "$WORK/led-dis" | jq -r 'select(.file == "a.c").fp')"
cat > "$WORK/cross2.json" <<EOF
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"findings":[],"disputes":[
 {"fp":"$d1","position":"refute","reason":"guarded at a.c:12"},
 {"fp":"nosuchfp0000","position":"confirm","reason":"dangling reference"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-dis" --source cross "$WORK/cross2.json" >/dev/null 2>&1
[ "$("$SRH/ledger.sh" unverified "$WORK/led-dis" --source cross | jq -r .title)" = "Claim two" ] \
  || fail "unverified must name exactly the claim cross never disputed"
[ "$("$SRH/ledger.sh" list "$WORK/led-dis" \
     | jq -r --arg fp "$d1" 'select(.fp == $fp).disputes[0].position')" = refute ] \
  || fail "dispute was not recorded on the finding"
did="$("$SRH/ledger.sh" demands "$WORK/led-dis" --status open | jq -r .id)"
[ -n "$did" ] || fail "benchmark demand was not ingested"
"$SRH/ledger.sh" demand "$WORK/led-dis" "$did" met --note "median -8% over 9 runs" >/dev/null
[ -z "$("$SRH/ledger.sh" demands "$WORK/led-dis" --status open)" ] || fail "met demand still open"
"$SRH/ledger.sh" report "$WORK/led-dis" | grep -q 'the rewrite is faster' \
  || fail "report drops benchmark demands"
pass "disputes and benchmark demands become tracked ledger state"

# An uninitialized directory must fail loudly instead of leaking a raw cat/jq
# error from inside a pipeline (where converged's exit code read as "not yet").
for c in round list report converged; do
  rc=0; "$SRH/ledger.sh" "$c" "$WORK/never-init" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "ledger.sh $c on an uninitialized dir must exit 2 (rc=$rc)"
done
pass "ledger commands refuse an uninitialized directory"

# A reopen adopts the re-report's severity and evidence: a round-1 minor
# re-reported as a blocker must block on its NEW severity, not the stale one.
"$SRH/ledger.sh" init "$WORK/led-esc" >/dev/null
cat > "$WORK/esc1.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"minor","file":"c.c","title":"Escalating issue","body":"weak"}]}
EOF
cat > "$WORK/esc2.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"blocker","file":"c.c","title":"Escalating issue","body":"crash repro"}]}
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
rc=0; "$SRH/ledger.sh" converged "$WORK/led-rej" --max-rounds 6 >/dev/null || rc=$?
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
# On a case-insensitive filesystem (macOS APFS default), a case-variant
# --out spelling must not bypass the refusal: the guard canonicalizes to
# on-disk case and compares inode identity. Skipped where case-sensitive.
RV="$(dirname "$R")/$(basename "$R" | tr '[:lower:]' '[:upper:]')"
if [ -d "$RV" ] && [ "$RV" -ef "$R" ]; then
  rc=0; "$SRH/bundle.sh" -C "$RV" --base main --uncommitted --out "$RV" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "bundle: case-variant root --out bypassed the refusal (rc=$rc)"
  [ ! -e "$R/diff.patch" ] || fail "bundle: case-variant refused run littered artifacts"
  pass "bundle.sh refuses a case-variant worktree-root --out (case-insensitive fs)"
else
  pass "case-variant --out pin skipped (case-sensitive filesystem)"
fi
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

# Shell-metacharacter filenames get their own list: substituted unquoted into
# a check command they are arbitrary code execution. Unusual-but-benign names
# (non-ASCII, spaces) must NOT be flagged or the signal is noise — and they
# must survive as real paths, not git's \NNN C-quoting, which nothing can open.
R3="$WORK/repo3"
git init -q -b main "$R3"
(
  cd "$R3"
  git config user.email srh@test && git config user.name srh
  mkdir -p src tests
  echo base > src/a.c
  git add -A && git commit -qm base
  git switch -qc names
  : > 'tests/x; echo PWNED #.sh'
  : > 'tests/plain_name_test.sh'
  : > 'src/тест.cpp'
  : > 'src/has space.c'
  git add -A && git commit -qm "unusual names"
)
B7="$("$SRH/bundle.sh" -C "$R3" --base main --out "$WORK/bundle7" 2>/dev/null | tail -1)"
[ "$(wc -l < "$B7/unsafe_paths.txt" | tr -d ' ')" = "1" ] \
  || fail "unsafe_paths.txt must flag exactly one path, got: $(cat "$B7/unsafe_paths.txt")"
grep -q 'echo PWNED' "$B7/unsafe_paths.txt" || fail "metacharacter path was not flagged"
grep -q 'unsafe_paths=1' "$B7/meta.env" || fail "meta.env lacks the unsafe_paths count"
grep -q "A${TAB}src/тест.cpp" "$B7/files.txt" \
  || fail "non-ASCII path was C-quoted in files.txt — it is not openable in that form"
grep -q "A${TAB}src/has space.c" "$B7/files.txt" || fail "a path with a space went missing"
pass "bundle.sh flags metacharacter paths and keeps benign unusual ones raw"

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

# --subst fills {placeholders} from a file of values, shell-quoting each. This
# is the injection pin: selectors come from the diff, commands run through
# `bash -c`, and an unquoted `tests/x; touch <marker> #.sh` would run.
marker="$WORK/PWNED"
printf 'tests/x; touch %s #.sh\ntests/plain_test.sh\n' "$marker" > "$WORK/sel.txt"
printf 'related%secho SEL: @@tests@@\n' "$TAB" > "$WORK/c-subst.tsv"
"$SRH/checks.sh" --file "$WORK/c-subst.tsv" --out "$WORK/cb6" -C "$WORK" \
  --subst tests="$WORK/sel.txt" >/dev/null
[ ! -e "$marker" ] || fail "--subst let a metacharacter path execute"
grep -q 'tests/plain_test.sh' "$WORK/cb6/checks/related.log" || fail "--subst dropped a selector"
grep -q 'touch' "$WORK/cb6/checks/related.log" \
  || fail "--subst did not pass the hostile path through as literal text"
pass "checks.sh --subst quotes selectors instead of executing them"

# A {placeholder} nobody filled means that check verified nothing. The command
# is NOT run — `true @@nobodyfilledthis@@` would exit 0 and record a pass that
# answers no question at all — and checks.tsv says fail, because that file is
# the evidence the gate actually reads.
printf 'lint%strue @@nobodyfilledthis@@\n' "$TAB" > "$WORK/c-unfilled.tsv"
rc=0
"$SRH/checks.sh" --file "$WORK/c-unfilled.tsv" --out "$WORK/cb7" -C "$WORK" \
  >"$WORK/unfilled.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "an unfilled placeholder must fail the run (rc=$rc)"
grep -q "lint${TAB}fail" "$WORK/cb7/checks.tsv" \
  || fail "an unfilled placeholder recorded pass in checks.tsv"
grep -q 'not run' "$WORK/cb7/checks/lint.log" \
  || fail "the log does not say the check was never run"
pass "checks.sh refuses to run, and never passes, a check with an unfilled placeholder"

# --- codex-review.sh ------------------------------------------------------
# Argument validation runs BEFORE the `command -v codex` guard, so all of it is
# testable with no CLI, no network and no credentials. Without these the
# --mode guard (itself a fix from an earlier review round) could be deleted
# and the suite would stay green while stage 3 silently ran a different mode.
printf 'prompt\n' > "$WORK/prompt.md"
for bad in "--mode bogus --prompt-file $WORK/prompt.md --out $WORK/o.json" \
           "--prompt-file $WORK/prompt.md" \
           "--out $WORK/o.json" \
           "--nope x"; do
  rc=0
  # shellcheck disable=SC2086
  env PATH=/usr/bin:/bin "$SRH/codex-review.sh" $bad >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "codex-review.sh '$bad' must exit 2, got $rc"
done
pass "codex-review.sh validates arguments before it needs the CLI"

# A missing CLI is its own exit code — the skill reports a skipped stage rather
# than absorbing it silently, so this must not be confused with a usage error.
rc=0
env PATH=/usr/bin:/bin "$SRH/codex-review.sh" --prompt-file "$WORK/prompt.md" \
  --out "$WORK/o.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 127 ] || fail "a missing codex CLI must exit 127, got $rc"
pass "codex-review.sh reports a missing CLI distinctly from a usage error"

# With a stub CLI on PATH: a non-JSON answer must NOT reach the ledger. This is
# the guard between a malformed cross-model reply and an ingest that quietly
# drops stage 3's findings.
mkdir -p "$WORK/stub"
cat > "$WORK/stub/codex" <<'EOF'
#!/usr/bin/env bash
# Minimal codex stand-in: honours -o <file> and writes whatever CODEX_STUB_BODY says.
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] && printf '%s' "${CODEX_STUB_BODY:-not json at all}" > "$out"
exit "${CODEX_STUB_RC:-0}"
EOF
chmod +x "$WORK/stub/codex"
rc=0
PATH="$WORK/stub:$PATH" "$SRH/codex-review.sh" --prompt-file "$WORK/prompt.md" \
  --out "$WORK/o.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "a non-JSON codex answer must exit 3, got $rc"

# …and a well-formed one succeeds, so the guard above is rejecting the body and
# not simply failing on everything.
rc=0
CODEX_STUB_BODY='{"verdict":"approve","summary":null,"findings":[],"benchmark_demands":[],"disputes":[]}' \
  PATH="$WORK/stub:$PATH" "$SRH/codex-review.sh" --prompt-file "$WORK/prompt.md" \
  --out "$WORK/o2.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "a schema-shaped codex answer must succeed, got $rc"
"$SRH/ledger.sh" init "$WORK/led-cx" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-cx" --source cross "$WORK/o2.json" >/dev/null \
  || fail "codex-review.sh output is not ledger-ingestible"
pass "codex-review.sh rejects a non-JSON answer and accepts a schema-shaped one"

# A check whose command is a pipeline must report the PIPELINE's failure, not
# its last stage's. `<test suite> 2>&1 | tail -3` is the idiom the example
# profile teaches, and without pipefail in the child shell a red suite records
# pass — the gate's entire purpose, silently inverted.
printf 'masked%ssh -c '"'"'exit 7'"'"' 2>&1 | tail -3\n' "$TAB" > "$WORK/c-pipe.tsv"
rc=0
"$SRH/checks.sh" --file "$WORK/c-pipe.tsv" --out "$WORK/cb8" -C "$WORK" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a failing check behind a pipe must fail the run (rc=$rc)"
grep -q "masked${TAB}fail" "$WORK/cb8/checks.tsv" || fail "a failing check behind a pipe recorded pass"
pass "checks.sh sees a failing command on the left of a pipe"

# Braces that belong to awk/jq/shell must not read as placeholders. Single
# braces are ambiguous — `awk 'BEGIN {print}'` and `jq '. | {name}'` are
# ordinary commands — so placeholders are {{doubled}}. Getting this wrong does
# not just warn: an unresolved placeholder means the check is NOT RUN and
# recorded fail, which blocks a required gate check on a legitimate command.
# shellcheck disable=SC2016  # ${v} and the awk/jq braces are the input under test
printf 'awkfmt%secho hi | awk '"'"'BEGIN {print}'"'"'\njqfmt%secho '"'"'{}'"'"' | jq '"'"'. | {name}'"'"'\nshvar%sv=ok; echo "${v}"\n' \
  "$TAB" "$TAB" "$TAB" > "$WORK/c-braces.tsv"
rc=0
"$SRH/checks.sh" --file "$WORK/c-braces.tsv" --out "$WORK/cb9" -C "$WORK" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "checks.sh blocked a legitimate awk/jq/shell brace (rc=$rc)"
grep -q "fail" "$WORK/cb9/checks.tsv" && fail "checks.sh recorded a brace-bearing command as fail"
pass "checks.sh runs commands whose braces belong to awk/jq/shell"

# --- ledger: state that must survive the operator ------------------------
# The operator is an agent in a multi-round loop; after a compaction it replays
# the runbook from the top. A second init used to wipe the ledger and reset the
# round, after which converged reported a clean run over unresolved findings.
"$SRH/ledger.sh" init "$WORK/led-reinit" >/dev/null
printf '{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"blocker","file":"a.c","title":"Real blocker","body":"b"}]}' > "$WORK/blk.json"
"$SRH/ledger.sh" add "$WORK/led-reinit" --source gate "$WORK/blk.json" >/dev/null
"$SRH/ledger.sh" bump "$WORK/led-reinit" >/dev/null
rc=0; "$SRH/ledger.sh" init "$WORK/led-reinit" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "re-init over a live ledger must be refused (rc=$rc)"
[ "$(wc -l < "$WORK/led-reinit/ledger.jsonl" | tr -d ' ')" = "1" ] || fail "re-init erased the ledger"
[ "$("$SRH/ledger.sh" round "$WORK/led-reinit")" = "2" ] || fail "re-init reset the round"
rc=0; "$SRH/ledger.sh" converged "$WORK/led-reinit" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "the surviving blocker must still block (rc=$rc)"
pass "ledger init refuses to wipe a live ledger"

# claims is the blind hand-off to stages 2-3: a second opinion that reads the
# first one's reasoning is an echo, not verification.
"$SRH/ledger.sh" init "$WORK/led-claims" >/dev/null
printf '{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"major","file":"a.c","line":7,"title":"Claim A","body":"STAGE2 REASONING","fix":"bound the copy"}]}' > "$WORK/cl.json"
"$SRH/ledger.sh" add "$WORK/led-claims" --source deep "$WORK/cl.json" >/dev/null
"$SRH/ledger.sh" claims "$WORK/led-claims" | grep -q 'STAGE2 REASONING' \
  && fail "claims leaked the finding body into the reviewer hand-off"
"$SRH/ledger.sh" claims "$WORK/led-claims" | grep -q 'a.c:7' || fail "claims dropped the location"
[ "$("$SRH/ledger.sh" list "$WORK/led-claims" | jq -r .fix)" = "bound the copy" ] \
  || fail "add dropped the schema-required fix field"
pass "claims hands over locations without reasoning; add keeps the fix field"

# A demand is an unmeasured claim. Converging over one means the report asserts
# evidence the run never gathered.
"$SRH/ledger.sh" init "$WORK/led-dem" >/dev/null
printf '{"verdict":"request-changes","summary":null,"disputes":[],"findings":[],"benchmark_demands":[{"claim":"hot loop faster","why":"w","suggested_method":"A/B"}]}' > "$WORK/dm.json"
"$SRH/ledger.sh" add "$WORK/led-dem" --source deep "$WORK/dm.json" >/dev/null 2>&1
rc=0; "$SRH/ledger.sh" converged "$WORK/led-dem" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "an open benchmark demand must block convergence (rc=$rc)"
"$SRH/ledger.sh" demand "$WORK/led-dem" \
  "$("$SRH/ledger.sh" demands "$WORK/led-dem" | jq -r .id)" dropped --note "not measurable here" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-dem" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "a dropped demand must stop blocking (rc=$rc)"
pass "open benchmark demands block convergence; resolving one releases it"

# unverified must not list findings the stage raised itself — a reviewer never
# disputes its own claims, so those are noise that scales with productivity.
"$SRH/ledger.sh" init "$WORK/led-unv" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-unv" --source deep "$WORK/cl.json" >/dev/null
printf '{"verdict":"request-changes","summary":null,"benchmark_demands":[],"findings":[{"severity":"major","file":"b.c","title":"Cross own finding","body":"x"}],"disputes":[]}' > "$WORK/cx.json"
"$SRH/ledger.sh" add "$WORK/led-unv" --source cross "$WORK/cx.json" >/dev/null 2>&1
"$SRH/ledger.sh" unverified "$WORK/led-unv" --source cross | jq -r .title | grep -q 'Cross own finding' \
  && fail "unverified listed the cross stage's own finding"
"$SRH/ledger.sh" unverified "$WORK/led-unv" --source cross | jq -r .title | grep -q 'Claim A' \
  || fail "unverified dropped the claim cross genuinely never addressed"
pass "unverified excludes a stage's own findings"

# An untracked name holding a newline must not split into two files.txt rows
# and slip past the unsafe-path scan — the plant-a-file case --uncommitted invites.
R4="$WORK/repo4"
git init -q -b main "$R4"
(
  cd "$R4"
  git config user.email srh@test && git config user.name srh
  echo a > f && git add -A && git commit -qm base
  git switch -qc names2
  printf 'plain\n' > "$(printf 'innocent.c\nrm -rf tmp')"
  printf 'ok\n' > normal.c
)
B8="$("$SRH/bundle.sh" -C "$R4" --base main --uncommitted --out "$WORK/bundle8" 2>/dev/null | tail -1)"
[ "$(wc -l < "$B8/files.txt" | tr -d ' ')" = "2" ] \
  || fail "a newline filename split files.txt into phantom rows: $(cat "$B8/files.txt")"
grep -q 'innocent' "$B8/unsafe_paths.txt" || fail "a newline filename escaped the unsafe-path scan"
grep -q 'dirty=1' "$B8/meta.env" || fail "meta.env did not record the dirty worktree"
pass "bundle.sh quotes newline filenames and records worktree dirtiness"

# A selector list that resolved to nothing means the check tested nothing.
# checks.tsv is the machine-readable evidence everything downstream keys on, so
# it must not say pass — stderr prose only helps if a model reads and obeys it.
: > "$WORK/sel-empty.txt"
printf 'related%strue @@tests@@\n' "$TAB" > "$WORK/c-empty.tsv"
rc=0
"$SRH/checks.sh" --file "$WORK/c-empty.tsv" --out "$WORK/cb10" -C "$WORK" \
  --subst tests="$WORK/sel-empty.txt" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "an empty selector list must fail the check (rc=$rc)"
grep -q "related${TAB}fail" "$WORK/cb10/checks.tsv" \
  || fail "an unverifiable check recorded pass in checks.tsv"
# `true` would EXIT 0 if it ran, so this only passes because the check was
# never run — without that, the probe would succeed and hide the regression.
grep -q 'not run' "$WORK/cb10/checks/related.log" \
  || fail "the empty-selector check was executed instead of being refused"
pass "checks.sh records an unverifiable check as fail, not pass"

# --halt stops at the first failure, so later rows must not appear.
printf 'first%sfalse\nsecond%strue\n' "$TAB" "$TAB" > "$WORK/c-halt.tsv"
"$SRH/checks.sh" --file "$WORK/c-halt.tsv" --out "$WORK/cb11" -C "$WORK" --halt >/dev/null 2>&1 || true
[ "$(wc -l < "$WORK/cb11/checks.tsv" | tr -d ' ')" = "1" ] \
  || fail "--halt kept running after a failure: $(cat "$WORK/cb11/checks.tsv")"
pass "checks.sh --halt stops at the first failing check"

# codex's own nonzero exit must propagate — swallowing it would make a crashed
# cross-model stage read as a silently-empty successful one.
rc=0
CODEX_STUB_RC=42 CODEX_STUB_BODY='{"verdict":"approve","summary":null,"findings":[],"benchmark_demands":[],"disputes":[]}' \
  PATH="$WORK/stub:$PATH" "$SRH/codex-review.sh" --prompt-file "$WORK/prompt.md" \
  --out "$WORK/o3.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 42 ] || fail "codex's own exit code must propagate, got $rc"
pass "codex-review.sh propagates codex's own failure"

# --paths scopes the reviewed diff; a regression that dropped the filter would
# quietly bundle the whole change and nobody would notice.
R5="$WORK/repo5"
git init -q -b main "$R5"
(
  cd "$R5"
  git config user.email srh@test && git config user.name srh
  mkdir -p src docs && echo a > src/a.c && echo d > docs/d.md
  git add -A && git commit -qm base
  git switch -qc scoped
  echo b >> src/a.c && echo e >> docs/d.md && git commit -qam change
)
B9="$("$SRH/bundle.sh" -C "$R5" --base main --paths 'src/*' --out "$WORK/bundle9" 2>/dev/null | tail -1)"
grep -q 'src/a.c' "$B9/files.txt" || fail "--paths dropped a path it should have kept"
grep -q 'docs/d.md' "$B9/files.txt" && fail "--paths did not exclude an unmatched path"
pass "bundle.sh --paths scopes the reviewed diff"

# A dispute whose position is neither confirm nor refute must be rejected:
# disputes are not schema-validated on ingest, so this guard is the only thing
# keeping a garbled cross-model reply out of a finding's recorded verdicts.
"$SRH/ledger.sh" init "$WORK/led-badpos" >/dev/null
"$SRH/ledger.sh" add "$WORK/led-badpos" --source deep "$WORK/cl.json" >/dev/null
bfp="$(jq -r .fp "$WORK/led-badpos/ledger.jsonl")"
cat > "$WORK/badpos.json" <<EOF
{"verdict":"approve","summary":null,"findings":[],"benchmark_demands":[],"disputes":[
 {"fp":"$bfp","position":"maybe","reason":"garbled"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-badpos" --source cross "$WORK/badpos.json" 2>"$WORK/badpos.err" >/dev/null
[ "$("$SRH/ledger.sh" list "$WORK/led-badpos" | jq -r '.disputes | length')" = "0" ] \
  || fail "a dispute with an out-of-enum position was recorded"
grep -q 'bad position' "$WORK/badpos.err" || fail "no warning for an out-of-enum dispute position"
pass "ledger rejects a dispute whose position is not confirm/refute"

# Stage receipts: `add` writes one per stage per round, and --require demands a
# current-round receipt with a non-blocking verdict. Without coverage, deleting
# the round match or the whole branch leaves both suites green.
"$SRH/ledger.sh" init "$WORK/led-req" >/dev/null
cat > "$WORK/clean.json" <<'EOF'
{"verdict":"approve","summary":null,"findings":[],"benchmark_demands":[],"disputes":[]}
EOF
rc=0; "$SRH/ledger.sh" converged "$WORK/led-req" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "an empty ledger with no stage receipt must not converge (rc=$rc)"
"$SRH/ledger.sh" add "$WORK/led-req" --source gate "$WORK/clean.json" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-req" --require gate >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "a same-round approving receipt must satisfy --require (rc=$rc)"
rc=0; "$SRH/ledger.sh" converged "$WORK/led-req" --require gate,cross --max-rounds 9 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a stage that never ran must block --require (rc=$rc)"
"$SRH/ledger.sh" bump "$WORK/led-req" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-req" --require gate --max-rounds 9 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a receipt from a PRIOR round must not satisfy --require (rc=$rc)"
# A stage that ran but returned "block" is evidence of a problem, not of clearance.
cat > "$WORK/blocked.json" <<'EOF'
{"verdict":"block","summary":null,"findings":[],"benchmark_demands":[],"disputes":[]}
EOF
"$SRH/ledger.sh" add "$WORK/led-req" --source gate "$WORK/blocked.json" >/dev/null
rc=0; "$SRH/ledger.sh" converged "$WORK/led-req" --require gate --max-rounds 9 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a blocking verdict must not satisfy --require (rc=$rc)"
# …and the cap must still terminate a run that can never satisfy --require.
rc=0; "$SRH/ledger.sh" converged "$WORK/led-req" --require gate --max-rounds 2 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "missing stage evidence must still hit MAX-ROUNDS EXHAUSTED (rc=$rc)"
pass "stage receipts gate convergence per round, per verdict, and still honour the cap"

# Adopting a re-report's evidence must drop verdicts cast on the OLD evidence,
# on every adoption path — otherwise `unverified` never re-lists the claim and
# a stale refute reads as a live verdict on evidence its author never saw.
"$SRH/ledger.sh" init "$WORK/led-stale" >/dev/null
cat > "$WORK/s1.json" <<'EOF'
{"verdict":"request-changes","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"major","file":"c.c","title":"Race in cache","body":"weak"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-stale" --source deep "$WORK/s1.json" >/dev/null
sfp="$(jq -r .fp "$WORK/led-stale/ledger.jsonl")"
cat > "$WORK/s2.json" <<EOF
{"verdict":"approve","summary":null,"findings":[],"benchmark_demands":[],"disputes":[{"fp":"$sfp","position":"refute","reason":"guarded"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-stale" --source cross "$WORK/s2.json" >/dev/null 2>&1
"$SRH/ledger.sh" bump "$WORK/led-stale" >/dev/null
cat > "$WORK/s3.json" <<'EOF'
{"verdict":"block","summary":null,"benchmark_demands":[],"disputes":[],"findings":[{"severity":"blocker","file":"c.c","title":"Race in cache","body":"NEW crash repro"}]}
EOF
"$SRH/ledger.sh" add "$WORK/led-stale" --source deep "$WORK/s3.json" >/dev/null
[ "$("$SRH/ledger.sh" list "$WORK/led-stale" | jq -r '.disputes | length')" = "0" ] \
  || fail "escalation kept a dispute cast on the superseded evidence"
"$SRH/ledger.sh" unverified "$WORK/led-stale" --source cross | grep -q 'Race in cache' \
  || fail "an escalated claim must go back on the cross stage's to-verify list"
pass "adopting new evidence clears verdicts cast on the old evidence"

echo "smoke-srh: all good"
