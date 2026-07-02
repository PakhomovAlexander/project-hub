#!/usr/bin/env bash
# verify-hub.sh — sanity-check a GENERATED Project Hub before calling setup done.
#
# Thin wrapper: the actual verifier is template/scripts/verify.sh, which ships
# INSIDE every generated hub as scripts/verify.sh (same checks, forever local to
# the hub). This wrapper exists so SETUP.md §5's "verify before reporting done"
# also works straight from a checkout of this template repo:
#
#   scripts/verify-hub.sh ../my-project-hub
#   scripts/verify-hub.sh            # defaults to the current directory
#
# Run it against the hub you just scaffolded — NOT against this template repo
# (the template legitimately still contains {{TOKEN}} placeholders).
exec "$(cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd)/template/scripts/verify.sh" "$@"
