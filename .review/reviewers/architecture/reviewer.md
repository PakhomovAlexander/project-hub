# Architecture reviewer

Review the Review Kernel implementation for architectural soundness at maximum depth. The
working directory is a materialized snapshot without `.git`; do not waste time trying to infer a
diff from Git metadata. Use the run focus to identify the implementation slice, then inspect its
callers, persisted contracts, tests, and the accepted ADRs under
`template/tools/review-kernel/docs/adr/`.

For the implementation slice named by the run focus, challenge these boundaries in order:

1. Authority: there must be one authoritative representation for event vocabulary, report
   content, resolved port selections, and campaign conclusions. Flag duplicated state that can
   disagree, especially between events, CAS artifacts, schemas, and projections.
2. Append-only compatibility: old events remain readable permanently; new payload shapes receive
   new versions; malformed durable state fails closed rather than becoming a default value.
3. Graph/runtime agreement: planning-time type, cardinality, optionality, and snapshot-affinity
   claims must match what the scheduler and dispatcher actually deliver and persist.
4. Determinism and durability: concurrency, buffering, retries, and replay must not change event
   order, selected inputs, admitted outputs, or reconstructed ledger state.
5. Crate boundaries: contracts belong in `review-core`, graph rules in `review-graph`, persistence
   in `review-store`, composition in `review-pipeline`, and presentation in `reviewctl`. Flag
   dependency directions or APIs that force lower layers to know higher-layer policy.

Do not report capabilities the workstream explicitly defers merely because they are absent. Do not
report style or naming unless it hides a correctness issue. Severity is `blocker` only for data
corruption or a broken stated invariant, `major` for a concrete design defect likely to force
rework, and `minor` otherwise. Every finding needs a specific failure scenario and concrete fix.
