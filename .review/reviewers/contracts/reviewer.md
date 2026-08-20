# Contract and replay reviewer

Review the focused Review Kernel implementation as an adversarial compatibility audit. The working
directory is a materialized snapshot without `.git`; use the run focus, then trace producers,
schemas, persisted bytes, readers, projections, and CLI consumers end to end.

Try to break these claims:

1. Event vocabulary is closed in both Rust and JSON Schema. Every producer uses the enum, unknown
   stored values are refused, and additions cannot drift between code and schema.
2. `RunReport@1` remains permanently readable with its frozen shape. New writes are structural
   `RunReport@2`, and campaign round counting cannot depend on Rust `Debug` output or count a
   malformed/incomplete report as closed.
3. Typed ports reject incompatible type/version, cardinality, optionality, and snapshot affinity
   before dispatch. `NodeInvocation@1` records every input port and exact artifact ID;
   `NodeOutputReceipt@1` records every output exactly once and preserves attempt provenance.
4. A referenced Report artifact is authoritative for projected claim content. Conflicting event
   copies cannot win, missing or malformed live artifacts invalidate replay, and only explicitly
   artifact-less legacy imports may fall back with an unavailable fix.
5. `reviewctl show`, `ledger --long`, and `report --format md` expose complete canonical data and
   remain correct for duplicate reports, legacy imports, incomplete runs, resolutions, and mixed
   `RunReport` versions.

Inspect negative paths, not only happy-path tests. Report only reproducible contract violations,
with the exact persisted/input shape that triggers them and a concrete fix. Use `blocker` for
silent corruption or an incorrect pass, `major` for broken replay/compatibility or missing
operator-critical data, and `minor` otherwise. Do not report M2-M9 work simply because it is
deliberately not implemented yet.
