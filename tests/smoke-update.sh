#!/usr/bin/env bash
# smoke-update.sh — drill the mechanical core of UPDATE.md.
#
# Scaffold a hub from a template repo at v1, evolve the template to v2 (a machinery
# change, a brand-new tokenized doc, and a change to a content file the hub owners
# customized), then apply the update the way UPDATE.md §4 prescribes and require:
#   - pristine machinery takes the template's v2
#   - a new template file lands with the hub's answers resolved (no leftover tokens)
#   - a customized content file is left alone (the hub's prose wins)
#   - the provenance sha bumps and the hub's scripts/verify.sh still passes
#
# Run from the template repo root:  tests/smoke-update.sh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/tests/lib.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TPL="$WORK/template-repo"
git_t() { git -C "$TPL" -c user.name=smoke -c user.email=smoke@test "$@"; }

# --- 1. a scratch template repo with history (v1 = the template as shipped) ----------
mkdir -p "$TPL"
cp -a "$ROOT/template" "$TPL/template"
cp "$ROOT/SETUP.md" "$ROOT/UPDATE.md" "$TPL/"
git_t init -q
git_t add -A
git_t commit -qm "template v1"
OLD="$(git_t rev-parse --short HEAD)"

# --- 2. a hub generated at v1, then customized by its owners --------------------------
HUB="$WORK/acme-hub"
scaffold_hub "$TPL" "$HUB" "$TPL" "$OLD"
BASE="$WORK/base" # pristine copy of the scaffold = UPDATE.md §3's reconstructed base
cp -a "$HUB" "$BASE"
printf '\n**Custom term**: the owners wrote this; an update must not touch it.\n' >> "$HUB/CONTEXT.md"

# --- 3. the template moves forward (v2) ------------------------------------------------
printf '\n# template-v2 machinery marker\n' >> "$TPL/template/scripts/worktree.sh"
cat > "$TPL/template/docs/release-drill.md" <<'EOF'
# {{PROJECT_NAME}} release drill

A doc the template grew after this hub was generated.
EOF
printf '\n**New template term**: upstream prose; must NOT replace the hub'"'"'s own.\n' >> "$TPL/template/CONTEXT.md"
git_t add -A
git_t commit -qm "template v2"
NEW="$(git_t rev-parse --short HEAD)"

# --- 4. apply the delta the way UPDATE.md §4 prescribes -------------------------------
applied="" skipped=""
while IFS= read -r t; do
  rel="${t#template/}"
  if [ -f "$BASE/$rel" ] && [ -f "$HUB/$rel" ] && ! cmp -s "$HUB/$rel" "$BASE/$rel"; then
    skipped="$skipped $rel" # customized → the hub's copy wins
    continue
  fi
  mkdir -p "$(dirname "$HUB/$rel")"
  git_t show "$NEW:$t" > "$HUB/$rel"       # pristine or new → take theirs…
  resolve_tokens "$TPL" "$NEW" "$HUB/$rel" # …re-resolved with the hub's answers
  case "$rel" in                           # …guidance stripped the way setup does
    *_template.md) : ;;
    *.md) perl -0pi -e 's/<!--\s*TEMPLATE:.*?-->\n?//gs' "$HUB/$rel" ;;
    *.sh | *.manifest) perl -ni -e 'print unless /^#\s*TEMPLATE/' "$HUB/$rel" ;;
  esac
  applied="$applied $rel"
done < <(git_t diff --name-only "$OLD..$NEW" -- template/)
perl -pi -e "s/^(\\s*sha:).*/\$1 $NEW/" "$HUB/.hub-meta.yml"
chmod +x "$HUB"/.claude/hooks/*.sh "$HUB"/scripts/*.sh
echo "applied:$applied"
echo "skipped:$skipped"

# --- 5. the update must have done exactly the right things ----------------------------
grep -q 'template-v2 machinery marker' "$HUB/scripts/worktree.sh" \
  || { echo "FAIL: machinery change did not land" >&2; exit 1; }
grep -q '^# acme release drill' "$HUB/docs/release-drill.md" \
  || { echo "FAIL: new template doc missing or its tokens unresolved" >&2; exit 1; }
grep -q 'Custom term' "$HUB/CONTEXT.md" \
  || { echo "FAIL: owner customization lost" >&2; exit 1; }
if grep -q 'New template term' "$HUB/CONTEXT.md"; then
  echo "FAIL: customized content file was overwritten by the template" >&2
  exit 1
fi
grep -q "sha: $NEW" "$HUB/.hub-meta.yml" \
  || { echo "FAIL: provenance sha not bumped" >&2; exit 1; }
echo "== verify updated hub =="
bash "$HUB/scripts/verify.sh" "$HUB"

echo
echo "OK — machinery updated, new doc resolved, hub content preserved, provenance bumped."
