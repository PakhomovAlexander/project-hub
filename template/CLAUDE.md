@AGENTS.md
@CONTEXT.md

# Claude Code notes — {{PROJECT_NAME}} Project Hub

<!-- TEMPLATE: keep this file THIN. The working agreement lives in AGENTS.md and the
     glossary in CONTEXT.md — both are imported above, so every Claude Code session loads
     them automatically. Don't copy rules here: one source of truth, no drift. Only
     genuinely Claude-specific wiring belongs below. Remove this comment. -->

The two imports above are binding: [`AGENTS.md`](AGENTS.md) is the **working agreement**,
[`CONTEXT.md`](CONTEXT.md) the **shared language**. What follows is Claude Code wiring only.

- Guardrails live in [`.claude/settings.json`](.claude/settings.json): safe hub commands
  are pre-allowed, risky families prompt before running (`permissions.ask` plus the
  PreToolUse hook), and `additionalDirectories` grants access to the linked clones in
  `{{CLONE_WORKSPACE}}`.
- Every session opens with a **hub brief** — tracker snapshot age + linked-repo status —
  injected by `.claude/hooks/session-brief.sh`.
- Skills: `/adr` · `/tracker` · `/resume` · `/onboard-repo` · `/verify` · `/update-hub` ·
  `/self-review-heavy`, loaded from [`.agents/skills/`](.agents/skills/) via the
  `.claude/skills` link. `/self-review-heavy`'s stage runners are the `srh-gate` and
  `srh-deep-reviewer` agents in [`.claude/agents/`](.claude/agents/).
