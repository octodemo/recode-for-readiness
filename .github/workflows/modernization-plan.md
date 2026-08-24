---
emoji: 🧭
name: Modernization Plan
description: >-
  Produces a reviewable, incremental modernization plan for one named routine
  in the legacy GEOSAT deck, as a pull request a human approves before any
  behaviour changes.
on:
  workflow_dispatch:
    inputs:
      routine:
        description: "Legacy routine to plan for (e.g. ORBPRP, TIMCNV, LIMCHK)"
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
checkout:
  fetch-depth: 0
safe-outputs:
  create-pull-request:
    title-prefix: "[modernization] "
    branch-prefix: "plan/"
    labels: [modernization, needs-human-review]
    draft: true
    if-no-changes: "error"
    allowed-files:
      - "docs/plans/**"
---

# Modernization Plan

Produce a modernization plan for the routine named in
`${{ inputs.routine }}`. Write the plan and nothing else. Do not modify the
legacy deck, the modern package, or any test.

## The constraint that shapes everything

This is flight-qualified ground software for a satellite in operation. The
output of `legacy/src/geosat.f` is parsed by a downstream archive loader by
fixed column position. A rewrite is not on the table. The only acceptable
shape of change is: characterize current behaviour, port it exactly, prove
equivalence, then change behaviour separately and deliberately.

## Before you plan

1. Read `legacy/graphify-out/graph.json` to establish what the routine
   connects to.
2. Read the routine in `legacy/src/geosat.f`, and the COMMON blocks it
   touches in `legacy/src/geosat.inc`.
3. Read the corresponding module under `modern/src/`, if one
   exists, and the tests that cover it in `modern/tests/`.
4. Read `legacy/tests/expected/` to see the behaviour that is currently
   pinned.

## What to write

`docs/plans/` already exists in the checkout and is tracked. Write your file
directly into it. Do **not** try to create the directory — the sandbox denies
every directory-creation call, and attempting it wastes the run. If the
directory somehow appears to be missing, call `report_incomplete` immediately
rather than trying to work around it.

Create `docs/plans/<routine-lowercase>.md` containing:

1. **Current behaviour** — what the routine does now, cited to
   `geosat.f:LINE`. Include the parts that look like bugs. Especially those.

2. **Preserved defects** — anything that is wrong but load-bearing, and what
   would break downstream if it were corrected. Each of these becomes a
   pinned test, not a fix.

3. **Coverage gap** — which of the current behaviours the golden vectors in
   `legacy/tests/golden/` do *not* exercise, and what new vector would be
   needed. Be concrete: describe the frame contents required.

4. **Incremental steps** — an ordered list where every step is independently
   reviewable, independently revertible, and leaves the characterization
   suite green. No step may combine a port with a behaviour change.

5. **Proof obligation per step** — how a reviewer confirms that step did what
   it claims. Naming a test is a proof; "verify correctness" is not.

6. **Explicitly out of scope** — what this plan does not touch, so the blast
   radius is legible to whoever approves it.

7. **Open questions for a human** — decisions you are not authorized to make.
   Anything that changes archived values belongs here.

## Rules

- Write only under `docs/plans/`. The safe-output configuration enforces this;
  do not attempt to work around it.
- This pull request is a draft on purpose. It is a proposal for a human to
  approve, and approval of the plan is not approval of any code change.
- If the named routine does not exist in the deck, say so and call `noop`
  rather than inventing a plan for a routine you did not find.
