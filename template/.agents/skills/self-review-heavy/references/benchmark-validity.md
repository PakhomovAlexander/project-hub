# What counts as benchmark evidence

A reviewer that demands a benchmark, and an orchestrator that runs one, hold
it to this bar — distilled from ClickHouse's perf-test methodology and the
LLVM benchmarking checklist (sources in [`prior-art.md`](prior-art.md)). A
bare "before 120 ms / after 105 ms" pair is inadmissible.

1. **Same-machine A/B against the merge base.** Build the old (merge-base)
   and new binaries; run both on the same machine, interleaved
   (old, new, old, new — never all of one then all of the other). Numbers
   from another day, machine, or dataset don't count.
2. **≥7 runs per side.** Report the median and the spread (min/max or
   stddev), never a single run. Close calls get more runs.
3. **5% effect floor, ~10% noise ceiling.** |Δ median| under 5% is "no
   change", however it trends. If run-to-run noise exceeds ~10%, the
   benchmark is *unstable* — fix the benchmark (longer workload, pinned
   data, quieter machine); don't interpret it.
4. **Counters over clocks when it's close.** On a small shared machine, wall
   clock is noisy; prefer perf counters (instructions, cycles, cache misses)
   and system-internal counters (items/bytes processed, CPU-time events) for
   verdicts near the floor.
5. **Result equivalence alongside speed.** The change must produce the same
   answer: byte-identical output artifacts where the system has them,
   identical query/computation results otherwise. A fast wrong answer is a
   blocker, not a win.
6. **Pinned recipe.** Dataset, sizes, settings, and workload list stated in
   the report so anyone can reproduce the run. Start from the profile's
   `benchmarks.recipe`.
7. **0.1–1 s per measured operation.** Below that, scheduling jitter
   dominates; far above, iterations are wasted.
