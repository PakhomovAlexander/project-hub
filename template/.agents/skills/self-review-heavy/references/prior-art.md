# Prior art — why the pipeline looks like this

Digest of the research behind this skill's design (July 2026). Each choice
below is load-bearing; the sources are primary.

## Findings that shaped the design

- **Independent passes surface non-overlapping findings.** Multi-review
  aggregation improved review F1 by up to ~44% on 1,000 verified PRs
  ([SWR-Bench](https://arxiv.org/abs/2509.01494)); Cursor's Bugbot ran 8
  shuffled passes + majority vote, later finder-over-flags + validator
  ([blog](https://cursor.com/blog/building-bugbot)); per-model strengths
  differ by bug class across vendors
  ([arXiv 2604.23361](https://arxiv.org/html/2604.23361v1)). Hence stage 3 is
  a *different vendor*, blind to stage 2's reasoning.
- **Precision is bought in a separate filter stage, not in the finder
  prompt.** Finder- and filter-tuned prompts are in tension
  ([Datadog](https://www.datadoghq.com/blog/using-llms-to-filter-out-false-positives/));
  recall pass → precision pass beats one clever prompt
  ([G-Research](https://www.gresearch.com/news/building-a-code-review-tool-the-llm-patterns-that-actually-work/));
  LLMs scoring their own comments' severity is "nearly random"
  ([Greptile](https://www.greptile.com/blog/make-llms-shut-up)). Hence
  cross-model `disputes` + the orchestrator's verify-before-fix triage.
- **Reproduce-or-drop beats argument.** Treat review like fuzzing: sampling
  plus a cheap verification mechanism tolerates a noisy finder
  ([Heelan on o3/CVE-2025-37899](https://sean.heelan.io/2025/05/22/how-i-used-o3-to-find-cve-2025-37899-a-remote-zeroday-vulnerability-in-the-linux-kernels-smb-implementation/)).
  For a database with a runnable perf harness, "demand a benchmark" is the
  strongest false-positive filter available. Hence `benchmark_demands` and
  the rule that an unmeasured perf finding can't stay blocking.
- **Self-correction without new external signal doesn't converge**
  ([Huang et al., ICLR 2024](https://arxiv.org/abs/2310.01798)). Every round
  here injects fresh evidence: check results, benchmark output, the other
  vendor's verdicts. Loops observed to converge in 3–5 rounds; CI budgets
  1–2 ([Zylos survey](https://zylos.ai/research/2026-03-01-multi-model-ai-code-review-convergence/)).
- **Churn control**: fingerprinted findings ledgers are standard SAST
  practice ([SARIF partialFingerprints](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support-for-code-scanning));
  round 2+ reviews the delta and suppresses new nits
  ([Claude Code REVIEW.md](https://code.claude.com/docs/en/code-review));
  role asymmetry — critics flag, one fixer owns the tree — stops
  cross-model oscillation ([Zylos](https://zylos.ai/research/2026-03-01-multi-model-ai-code-review-convergence/)).
- **Reviewers get file paths and SHA-bounded scope, never session history**
  ([superpowers requesting-code-review](https://github.com/obra/superpowers/blob/main/skills/requesting-code-review/SKILL.md));
  the fixer verifies findings against reality and may push back with
  reasons — performative agreement is banned
  ([superpowers receiving-code-review](https://github.com/obra/superpowers/blob/main/skills/receiving-code-review/SKILL.md));
  cross-vendor loop with author pushback converges without diff churn
  ([Claude↔Codex loop](https://charlesjones.dev/blog/claude-code-codex-pr-review-loop)).
- **Diffs above ~500 lines degrade review sharply** — chunk by subsystem and
  close with one sweep ([Zylos](https://zylos.ai/research/2026-03-01-multi-model-ai-code-review-convergence/),
  [Cloudflare's risk tiering](https://blog.cloudflare.com/ai-code-review/)).
- **Benchmark validity bar** comes from ClickHouse's own methodology —
  same-machine interleaved A/B, 7 runs, median + permutation-derived noise
  threshold, 5% effect floor, "unstable" as its own failure class
  ([blog](https://clickhouse.com/blog/testing-the-performance-of-click-house),
  [report guide](https://github.com/ClickHouse/ClickHouse/blob/master/tests/performance/scripts/README.md),
  [rewrite RFC](https://github.com/ClickHouse/ClickHouse/issues/102543)) —
  plus the [LLVM benchmarking checklist](https://llvm.org/docs/Benchmarking.html).
- **Codex CLI mechanics**: `codex exec` defaults to a read-only sandbox,
  `--output-schema` enforces JSON, `-o` captures the final message; set
  `approval_policy=never` for headless runs; pin model + effort per
  invocation, not via session defaults
  ([non-interactive docs](https://developers.openai.com/codex/noninteractive),
  [CLI reference](https://developers.openai.com/codex/cli/reference)).
- **Skill portability**: layout and frontmatter follow the
  [Open Agent Skills spec](https://agentskills.io/specification) (`name`,
  `description`, optional `compatibility`/`metadata`; unknown keys must be
  ignored), so non-Claude harnesses can run this skill from the same files.
