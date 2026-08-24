---
emoji: 🔍
name: Legacy Comprehension
description: >-
  Explains a routine in the legacy GEOSAT FORTRAN deck in plain language,
  grounded in the graphify knowledge graph, when an issue asks for it.
on:
  issues:
    types: [opened, labeled]
permissions:
  contents: read
  issues: read
  copilot-requests: write
strict: true
engine: copilot
network:
  allowed: [defaults]
tools:
  github:
    mode: gh-proxy
    toolsets: [issues, repos]
  bash:
    - "python3"
    - "grep *"
    - "sed *"
safe-outputs:
  add-comment:
    max: 1
---

# Legacy Comprehension

An engineer has asked what part of a 1987 satellite ground-system deck
actually does. The original authors are gone and there is no design document.
Your job is to recover the knowledge, not to change the code.

## Scope guard

Only act when the issue asks about the legacy telemetry processor. If the
issue is about anything else, call `noop` and post nothing.

## Sources, in this order

1. **`legacy/graphify-out/graph.json`** — a knowledge graph of the deck built
   locally by tree-sitter with no model involved. Every edge is tagged
   `EXTRACTED` (read directly from the source) or `INFERRED` (resolved by
   graphify). Use it to find the call structure before you read anything.

   Read it with `python3`. Useful shapes:
   - which routines call the subject, and which it calls
   - the shortest path between two routines
   - the most connected routines, which are the de facto architecture

2. **`legacy/src/geosat.f`** — the deck itself. The whole flight chain is one
   compilation unit; see the file header for why. Read the actual lines the
   graph points you at.

3. **`legacy/src/geosat.inc`** — the COMMON block layout. Data flow in this
   program is mostly through COMMON, not through argument lists, so the call
   graph alone will understate the coupling.

4. **`legacy/tests/expected/*.out`** — what the program actually emits today.

## What to produce

Post one comment containing:

1. **What it does** — two or three sentences, in language a new engineer with
   no FORTRAN background can follow.
2. **Where it sits** — what calls it, what it calls, and which COMMON blocks
   it reads and writes. Cite `geosat.f:LINE` for each.
3. **Inputs and outputs** — including anything passed through COMMON rather
   than through the argument list.
4. **Behaviour worth knowing before touching it** — the surprising parts.
   Historical comments referencing ECOs, memos, or the ICD are load-bearing;
   surface them rather than skipping them.
5. **What you could not determine** — explicitly. An honest gap is more
   useful here than a confident guess, because the next engineer will act on
   what you write.

## Rules

- Ground every structural claim in either a graph edge or a source line, and
  say which. If the graph and the source disagree, trust the source and say
  that the graph is stale.
- The graph resolves calls within a compilation unit. It does not model
  COMMON block data flow. Do not present it as a complete dependency picture.
- Do not propose a refactor. This workflow recovers understanding; planning a
  change is a separate, human-initiated step.
