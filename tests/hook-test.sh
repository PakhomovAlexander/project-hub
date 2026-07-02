#!/usr/bin/env bash
# hook-test.sh — table-driven regression test for the risky-commands hook.
#
# Each case is "expected|command": expected is `ask` (hook must emit a
# permissionDecision:ask) or `none` (hook must stay silent so the normal
# permission flow decides). The hook must exit 0 either way.
#
# Run from the template repo root:  tests/hook-test.sh
set -u

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/template/.claude/hooks/ask-before-risky-commands.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 2; }

CASES=(
  # --- must prompt: pushes and deploys -------------------------------------------
  "ask|git push origin main"
  "ask|git push --force"
  "ask|git -C repos/foo push"
  "ask|GIT_DIR=x git push"
  "ask|git stash && git push"
  "ask|bash -c 'git push'"
  "ask|docker push registry/img:tag"
  "ask|./scripts/deploy.sh prod"
  "ask|npm run deploy"
  # --- must prompt: cloud / infra CLIs -------------------------------------------
  "ask|aws s3 ls"
  "ask|gcloud compute instances list"
  "ask|az group delete -n x"
  "ask|kubectl get pods"
  "ask|helm upgrade release chart"
  "ask|terraform apply"
  "ask|terragrunt plan"
  # --- must prompt: destructive file ops -----------------------------------------
  "ask|rm -rf build/"
  "ask|rm -fr build/"
  "ask|rm --recursive build/"
  "ask|rm build -r"
  "ask|git clean -fdx"
  "ask|find . -name '*.tmp' -delete"
  # --- must prompt: shipping / registry mutations --------------------------------
  "ask|npm publish"
  "ask|cargo publish"
  "ask|gem publish"
  "ask|twine upload dist/*"
  "ask|gh pr merge 42"
  "ask|gh repo delete acme/x --yes"
  "ask|gh release create v1.0.0"
  "ask|gh api -X DELETE repos/a/b"
  # --- must stay silent: everyday work -------------------------------------------
  "none|ls -la"
  "none|make status"
  "none|make list"
  "none|git status"
  "none|git commit -m 'x'"
  "none|git log --oneline"
  "none|git pull"
  "none|rm file.txt"
  "none|rm -f file.txt"
  "none|docker build ."
  "none|docker compose up -d"
  "none|gh pr view 42"
  "none|gh api repos/a/b"
  "none|npm install"
  "none|npm test"
  "none|find . -name '*.md'"
  "none|grep -r TODO src/"
  "none|echo hello"
)

fail=0
for case in "${CASES[@]}"; do
  exp="${case%%|*}"
  cmd="${case#*|}"
  out="$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$HOOK")"
  rc=$?
  if [ -n "$out" ]; then got="ask"; else got="none"; fi
  if [ "$got" = "ask" ] && ! printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then
    got="malformed"
  fi
  if [ "$got" != "$exp" ] || [ "$rc" -ne 0 ]; then
    printf 'FAIL exp=%-4s got=%-9s rc=%d  %s\n' "$exp" "$got" "$rc" "$cmd"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "OK — all ${#CASES[@]} hook cases pass."
else
  echo "FAIL — hook regressions above." >&2
fi
exit "$fail"
