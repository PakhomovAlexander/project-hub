# lib.sh — shared helpers for the template's tests. Source it; don't execute.
# shellcheck shell=bash

# token_program <template-url> <template-sha>
# Emit the perl program that resolves every SETUP.md §6 token the way a real setup
# would, using the tests' fixed "acme" interview answers.
token_program() {
  local url="$1" sha="$2" today
  today="$(date +%Y-%m-%d)"
  printf '%s\n' \
    's/\{\{PROJECT_NAME\}\}/acme/g;' \
    's/\{\{PROJECT_TAGLINE\}\}/A demo app/g;' \
    's/\{\{ORG\}\}/acme-inc/g;' \
    's|\{\{CLONE_WORKSPACE\}\}|../acme-ws|g;' \
    's|\{\{HUB_REPO\}\}|acme-inc/hub|g;' \
    's/\{\{DEFAULT_OWNER\}\}/octocat/g;' \
    "s/\\{\\{TODAY\\}\\}/$today/g;" \
    "s|\\{\\{TEMPLATE_URL\\}\\}|$url|g;" \
    "s/\\{\\{TEMPLATE_SHA\\}\\}/$sha/g;" \
    's/\{\{HUB_LAYOUT\}\}/multi-repo/g;'
}

# resolve_tokens <template-url> <template-sha> <file>...
# Resolve the §6 tokens in the given files (perl -pi: portable across GNU/BSD).
resolve_tokens() {
  local url="$1" sha="$2"
  shift 2
  perl -pi -e "$(token_program "$url" "$sha")" "$@"
}

# scaffold_hub <template-repo-root> <hub-dir> <template-url> <template-sha>
# Scaffold a hub from <root>/template the way SETUP.md §3–§5 prescribes, playing the
# agent's mechanical moves: copy with dotfiles + the .claude/skills symlink, resolve
# the §6 tokens, fill inline placeholders, strip guidance comments, chmod hooks/scripts.
scaffold_hub() {
  local root="$1" hub="$2" url="$3" sha="$4"

  # copy the skeleton (cp -a: keeps dotfiles + the .claude/skills symlink)
  mkdir -p "$hub"
  cp -a "$root/template/." "$hub/"
  [ -L "$hub/.claude/skills" ] || { echo "FAIL: .claude/skills symlink lost in copy" >&2; return 1; }

  # resolve the SETUP.md §6 tokens
  find "$hub" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.json' \
      -o -name '*.manifest' -o -name '*.yml' -o -name 'Makefile' \) -print0 \
    | xargs -0 perl -pi -e "$(token_program "$url" "$sha")"

  # play the agent: fill inline placeholders, drop guidance comments —
  # multi-line <!-- TEMPLATE: … --> blocks in .md (the _template.md scaffolds keep theirs)
  find "$hub" -type f -name '*.md' -not -name '_template.md' -print0 \
    | xargs -0 perl -0pi -e 's/<!--\s*TEMPLATE:.*?-->\n?//gs'
  # "# TEMPLATE…" comment lines in scripts + the manifest
  find "$hub" -type f \( -name '*.sh' -o -name '*.manifest' \) -print0 \
    | xargs -0 perl -ni -e 'print unless /^#\s*TEMPLATE/'
  # remaining {{inline placeholders}} become plain filler text (-0: they span lines)
  find "$hub" -type f \( \( -name '*.md' -a -not -name '_template.md' \) \
      -o -name '*.manifest' \) -print0 \
    | xargs -0 perl -0pi -e 's/\{\{[^}]*\}\}/X/gs'

  # wire up like SETUP.md §5
  chmod +x "$hub"/.claude/hooks/*.sh "$hub"/scripts/*.sh
}
