---
name: explain-asci
description: Explain how code works using ASCII diagrams and one concrete example traced end to end — physical layout, index spaces, branches, and the invariants that fall out. Use when someone asks to understand a data structure, algorithm, or subsystem precisely.
argument-hint: <file/symbol/subsystem> [what specifically is confusing]
---

# Explain code with ASCII and a worked example

Prose explains what code is for. It is often poor at showing what code does to
data. This skill carries one concrete example through every stage, so the reader
watches values move instead of receiving a sequence of disconnected summaries.

Output goes in the reply. Do not create a rendered artifact unless the user asks
for one; the explanation should land where they are already reading the code.

## 1. Read before drawing

Read the implementation to the end, including the helpers it calls. Identify:

- **Index spaces.** State what every array, map, or table is indexed by. If
  `offset_to_bucket` is indexed by `offsets[row]` rather than `row`, every arrow
  in the diagram must preserve that distinction.
- **The central difficulty.** Name the relation that makes the implementation
  look more complicated than expected. It is often a relation assumed to be
  one-to-one that is actually many-to-many.
- **Branches.** Find every distinct path the data can take.
- **Deliberate weirdness.** Find code that looks wrong but is safe because of a
  less-obvious invariant.

## 2. Build one example that exercises the whole path

Use one small example throughout the explanation, not a fresh toy per section.
Choose values that exercise every branch and both directions of any many-to-many
relation. Where applicable, include:

- several inputs collapsing into one output;
- one input splitting into several outputs;
- a null, empty, missing, or error case;
- a boundary value that changes a decision.

Six to ten rows is usually enough. Prefer visibly different values such as `5`,
`-3`, `"abc"`, and `42` over names such as `x1`, `x2`, and `x3`.

## 3. Verify the example against the implementation

Trace the chosen values through the actual classification and dispatch code. If
the example says a value selects a type, bucket, state, or branch, find and cite
the code that makes that decision.

An exact-looking diagram is more dangerous than vague prose when it is wrong. If
something cannot be established from the implementation, label it as unknown or
an inference; never draw a guess as a factual arrow.

## 4. Draw physical layout first

Show the arrays, columns, objects, or files as they physically exist before
explaining their meaning. For example:

```text
                 row:   0    1    2    3
                      +----+----+----+----+
  local_slot:         | 0  | 2  | -- | 1  |
                      +----+----+----+----+
  offsets:            | 1  | 0  | -- | 2  |
                      +----+----+----+----+
                        |
                        v
  slot 0 values:      [ 5, -3 ]
```

Then explain the subsystem in this order:

1. Name and draw the central relation.
2. Trace construction step by step, including a hit on an existing entry rather
   than only first-time insertions.
3. Draw the resulting tables side by side and mark mutually exclusive fields.
4. Draw the branch or dispatch path.
5. Trace every row in a table; do not skip the inconvenient one with “and so on.”
6. Draw the output and identify the path each value took.

For a control-flow subsystem rather than an in-memory structure, use the same
discipline with processes, repositories, files, requests, or state transitions as
the physical units.

## 5. Close on the surprising bit and the invariants

Add a section titled **The bit that looks like a bug** for anything a careful
reader is likely to flag. Show the surprising value or transition explicitly,
then show the invariant that makes it safe. If there is no such bit, do not invent
one.

Finish with a short list of invariants phrased for a future editor: what must
remain true, and what a change would break.

## Format rules

- Keep diagram lines under about 100 characters so terminal wrapping does not
  destroy alignment.
- Use ASCII-safe characters: `+ - | v ^ < >`.
- Align trace columns.
- Cite `file:line` at each stage so the reader can jump to the implementation.
- Use the codebase's real identifiers, not simplified aliases the reader cannot
  search for.

## Do not

- Explain code you have not read to the end.
- Diagram a trivial path that one sentence explains better.
- Use structure diagrams as proof of runtime behaviour when a test or profiler is
  the appropriate evidence.
- Let a diagram imply certainty the implementation does not provide.

## Afterwards

If the explanation captures durable knowledge or a costly gotcha, offer to record
it in the appropriate repository reference, design note, or ADR. Durable project
knowledge belongs in the hub rather than only in a chat transcript.
