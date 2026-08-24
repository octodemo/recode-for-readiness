---
emoji: 🔧
name: Modernization Implement
description: >-
  Re-derives the Rust port of one named routine directly from the 1987 FORTRAN
  and proves it by byte-for-byte equivalence against the compiled legacy
  binary. Opens a draft pull request a human approves.
on:
  workflow_dispatch:
    inputs:
      routine:
        description: "Legacy routine to implement (e.g. TIMCNV, CRCCHK, ENGCNV)"
        required: true
        type: string
permissions:
  contents: read
  copilot-requests: write
strict: true
engine: copilot
network:
  allowed: [defaults]
tools:
  github:
    mode: gh-proxy
    toolsets: [repos]
  bash:
    - "cargo"
    - "jq *"
    - "make"
    - "grep *"
    - "sed *"
    - "diff *"
    - "./legacy/build/geosat"
checkout:
  fetch-depth: 0
safe-outputs:
  create-pull-request:
    title-prefix: "[port] "
    branch-prefix: "port/"
    labels: [modernization, needs-human-review]
    draft: true
    if-no-changes: "error"
    allowed-files:
      - "modern/src/**"
---

# Modernization Implement

Re-derive the Rust port of `${{ inputs.routine }}` from the legacy FORTRAN.

A port of this routine already exists in `modern/src/`. **Ignore it as a
source.** Do not copy it, do not lightly edit it. Work from
`legacy/src/geosat.f` and rewrite the module body from the FORTRAN, as if
porting it for the first time. Then replace the existing implementation with
yours.

This is deliberate. The existing port is a human's work, and the question on
the table is whether the same routine can be derived again, independently, and
still land byte-for-byte on 1987 output. If your version passes the suite, it
is a valid port. If it does not, the existing one stands and yours is wrong.

You may read the existing module for its **public signature only** -- the
function names and types other modules call. Do not change that surface.

## What you may and may not write

You may write **only** files under `modern/src/`. That is enforced by the
safe-output configuration, not by your good behaviour, and it is deliberate:

- `legacy/src/**` is the **oracle**. It defines correct. If you could edit it,
  "the port matches the legacy deck" would mean nothing.
- `legacy/tests/golden/**` and `legacy/tests/expected/**` are the **evidence**.
  Byte-for-byte equivalence against a file you were allowed to rewrite is not
  evidence of anything.
- `modern/tests/**` is the **judge**. You do not get to grade your own
  homework. If a test fails, the test is right and you are wrong.

If you believe a test is genuinely incorrect, do not work around it. Say so in
the pull request body and let a human decide.

## The constraint that shapes everything

This is flight-qualified ground software for a satellite in operation. The
output of `legacy/src/geosat.f` is parsed by a downstream archive loader by
fixed column position. The bar is not "works" or "looks idiomatic". The bar is
**byte-for-byte identical output on every golden vector**.

That includes reproducing behaviour that looks wrong. If the legacy routine has
a defect, port the defect. Record it in the pull request body under a heading
`Preserved defects` so a human can schedule fixing it as its own change with
its own updated vectors. Fixing a defect while porting it destroys the only
proof you have that the port is faithful.

## Before you write anything

1. Read `docs/plans/<routine-lowercase>.md` if it exists. That plan was
   reviewed by a human. Follow it. If you are going to deviate, say why in the
   pull request body.
2. Read the routine in `legacy/src/geosat.f`. Read the COMMON blocks it touches
   in `legacy/src/geosat.inc`.
3. Read `legacy/graphify-out/graph.json` to see what calls the routine and what
   it calls, so you know the blast radius.
4. Read `modern/src/precision.rs`. It defines the numeric contract for this
   port -- when to use `f32`, how transcendentals are evaluated, why expression
   order matters. Every arithmetic decision you make must follow it.
5. Read a neighbouring module that is already ported -- `modern/src/crc.rs` is
   short and representative -- to match the house style.

## Numeric rules, non-negotiable

The legacy deck declares everything `REAL(4)`. Getting this wrong produces
output that is correct to three decimal places and still fails.

- Every intermediate value is `f32`. Do not compute in `f64` and round at the
  end -- that double-rounds and diverges.
- Preserve **expression order exactly** as written in the FORTRAN. `a * b * c`
  rounds after each operation. Reassociating changes the result.
- Transcendentals go through `modern/src/precision.rs`, never `f32::sin` and
  friends directly.
- Integer-to-float conversion is `as f32`, matching FORTRAN `REAL(INT)`.

## Proving it

Run these. All of them. Do not open a pull request until they pass.

```
cd modern && cargo test
```

That runs the characterization suite, which pipes all four golden vectors
through both the compiled 1987 binary and your Rust port and compares the
output byte for byte. It also runs the unit suite.

If `cargo test` fails, you are not done. Read the diff, fix the port, run it
again. Do not weaken a test -- you cannot, the fencing forbids it, and
attempting it will fail the run.

## The pull request body

Write it for a reviewer who will not read your diff line by line:

1. **What the routine does** -- in plain language, cited to `geosat.f:LINE`.
2. **How the port proves it** -- name the vectors, state that `cargo test`
   passes, give the count.
3. **Preserved defects** -- anything you reproduced on purpose that looks
   wrong, and what fixing it later would require.
4. **Numeric decisions** -- any place expression order or precision was
   load-bearing, so the reviewer knows where to look hardest.
5. **What you did not do** -- gaps, assumptions, anything you were unsure of.

## Rules

- Write only under `modern/src/`. The safe-output configuration enforces this.
- Never edit the legacy deck, the golden vectors, the expected output, or the
  tests.
- A draft pull request is the only output. Approving a port is a human's call.
- Your pull request must actually change the module. Re-deriving it and
  arriving at something byte-identical to the existing source is possible for a
  short routine; if that happens, say so in the body rather than inventing a
  cosmetic change.
- If the named routine does not exist in the deck, say so and call
  `report_incomplete`.
