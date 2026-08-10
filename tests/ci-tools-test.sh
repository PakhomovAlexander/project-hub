#!/usr/bin/env bash
# ci-tools-test.sh — offline behavioural tests for push.sh and watch-ci.sh.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PUSH="$ROOT/template/scripts/push.sh"
WATCH="$ROOT/template/scripts/watch-ci.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ok() { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
must_contain() {
  if grep -qF -- "$2" "$1"; then ok "$3"; else bad "$3"; fi
}
must_rc() {
  if [ "$1" -eq "$2" ]; then ok "$3"; else bad "$3 (rc=$1, expected $2)"; fi
}

# A deterministic gh stub. Git remains real and pushes only to a temporary bare repo.
FAKEBIN="$TMP/bin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
set -u
mode="${GH_MODE:-empty}"
log="${GH_LOG:?}"
state="${GH_STATE:?}"
printf '%s\n' "$*" >> "$log"
case "${1:-} ${2:-}" in
  "run list")
    [ "$mode" != "list-fail" ] || { echo "list unavailable" >&2; exit 7; }
    case "$mode" in
      live|cancel-fail) printf '101\tqueued\tBuild\tabcdef123456\n' ;;
    esac
    ;;
  "run cancel")
    [ "$mode" != "cancel-fail" ] || { echo "cancel unavailable" >&2; exit 8; }
    ;;
  "pr checks")
    count=0
    [ -f "$state" ] && count="$(cat "$state")"
    count=$((count + 1)); printf '%s' "$count" > "$state"
    case "$mode" in
      watch-pass)
        if [ "$count" -eq 1 ]; then
          printf '[{"name":"Build","bucket":"pending"}]\n'
        else
          printf '[{"name":"Build","bucket":"pass"}]\n'
        fi
        ;;
      watch-fail) printf '[{"name":"Tests","bucket":"fail"}]\n' ;;
      watch-cancel) printf '[{"name":"Deploy","bucket":"cancel"}]\n' ;;
      watch-empty) printf '[]\n' ;;
      watch-api-fail) echo "API unavailable" >&2; exit 9 ;;
      *) printf '[{"name":"Checks","bucket":"pass"}]\n' ;;
    esac
    ;;
  *) echo "unexpected gh command: $*" >&2; exit 10 ;;
esac
EOF
chmod +x "$FAKEBIN/gh"
export PATH="$FAKEBIN:$PATH" GH_LOG="$TMP/gh.log" GH_STATE="$TMP/gh.state"

REMOTE="$TMP/remote.git"
REPO="$TMP/repo"
git init -q --bare "$REMOTE"
git init -q -b main "$REPO"
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.invalid
printf 'base\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -qm base
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" push -q -u origin main
git -C "$REPO" remote set-head origin main

echo "== push.sh =="
set +e
GH_MODE=empty "$PUSH" -C "$REPO" --repo example/project --dry-run > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 2 "default branch is refused"
must_contain "$TMP/out" "refusing to push default branch" "default-branch diagnostic is clear"

git -C "$REPO" switch -qc feature/tooling
printf 'one\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam one
GH_MODE=empty "$PUSH" -C "$REPO" --repo example/project > "$TMP/out" 2>&1
local_head="$(git -C "$REPO" rev-parse HEAD)"
remote_head="$(git --git-dir="$REMOTE" rev-parse refs/heads/feature/tooling)"
if [ "$local_head" = "$remote_head" ]; then
  ok "ordinary feature push succeeds"
else
  bad "ordinary feature push succeeds"
fi

printf 'two\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam two
before="$(git --git-dir="$REMOTE" rev-parse refs/heads/feature/tooling)"
GH_MODE=live "$PUSH" -C "$REPO" --repo example/project --dry-run > "$TMP/out" 2>&1
after="$(git --git-dir="$REMOTE" rev-parse refs/heads/feature/tooling)"
if [ "$before" = "$after" ]; then
  ok "dry-run neither cancels nor pushes"
else
  bad "dry-run neither cancels nor pushes"
fi
must_contain "$TMP/out" "101" "dry-run reports the live run"

set +e
GH_MODE=list-fail "$PUSH" -C "$REPO" --repo example/project --yes > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 2 "CI lookup failure fails closed"
if [ "$before" = "$(git --git-dir="$REMOTE" rev-parse refs/heads/feature/tooling)" ]; then
  ok "lookup failure does not push"
else
  bad "lookup failure does not push"
fi

set +e
GH_MODE=cancel-fail "$PUSH" -C "$REPO" --repo example/project --yes > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 2 "cancellation failure fails closed"
if [ "$before" = "$(git --git-dir="$REMOTE" rev-parse refs/heads/feature/tooling)" ]; then
  ok "cancellation failure does not push"
else
  bad "cancellation failure does not push"
fi

GH_MODE=live "$PUSH" -C "$REPO" --repo example/project --yes > "$TMP/out" 2>&1
if [ "$(git -C "$REPO" rev-parse HEAD)" = \
  "$(git --git-dir="$REMOTE" rev-parse refs/heads/feature/tooling)" ]; then
  ok "confirmed cancellation is followed by push"
else
  bad "confirmed cancellation is followed by push"
fi

git -C "$REPO" remote set-url origin git@github.com:example/project.git
GH_MODE=empty "$PUSH" -C "$REPO" --dry-run > "$TMP/out" 2>&1
must_contain "$TMP/out" "repo=example/project" "GitHub repository is inferred from SSH origin"
git -C "$REPO" remote set-url origin "$REMOTE"

echo "== watch-ci.sh =="
: > "$GH_STATE"
GH_MODE=watch-pass "$WATCH" 42 -C "$REPO" --repo example/project \
  --interval 0 --gates '^Build$' > "$TMP/out" 2>&1
must_contain "$TMP/out" "Build: pass" "selected successful gate is reported"
must_contain "$TMP/out" "all checks terminal — 0 failed, 0 cancelled" \
  "passing checks produce a terminal summary"

: > "$GH_STATE"
GH_MODE=empty "$WATCH" https://github.com/example/project/pull/42 \
  --interval 0 > "$TMP/out" 2>&1
must_contain "$GH_LOG" "pr checks 42 --repo example/project" \
  "pull-request URL supplies repository and number"

: > "$GH_STATE"
set +e
GH_MODE=watch-fail "$WATCH" 42 -C "$REPO" --repo example/project \
  --interval 0 > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 1 "failed check returns exit 1"
must_contain "$TMP/out" "Tests: fail" "failure present at attach is reported"

: > "$GH_STATE"
set +e
GH_MODE=watch-cancel "$WATCH" 42 -C "$REPO" --repo example/project \
  --interval 0 > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 1 "cancelled check returns exit 1"
must_contain "$TMP/out" "Deploy: cancel" "cancellation present at attach is reported"

: > "$GH_STATE"
set +e
GH_MODE=watch-api-fail "$WATCH" 42 -C "$REPO" --repo example/project \
  --interval 0 --max-errors 2 > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 2 "repeated API failure returns exit 2"
must_contain "$TMP/out" "failed repeatedly" "API failure diagnostic names the terminal cause"

: > "$GH_STATE"
set +e
GH_MODE=watch-empty "$WATCH" 42 -C "$REPO" --repo example/project \
  --interval 0 --max-errors 2 > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 2 "checks that never appear return exit 2"

set +e
GH_MODE=empty "$WATCH" 42 -C "$REPO" --repo example/project \
  --gates '[' > "$TMP/out" 2>&1
rc=$?
set -e
must_rc "$rc" 2 "invalid gate regex returns exit 2"

if [ "$fail" -eq 0 ]; then
  echo "OK — CI push/watch helpers behave."
else
  echo "FAIL — CI helper regressions above." >&2
fi
exit "$fail"
