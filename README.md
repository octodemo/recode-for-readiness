# Recode for Readiness — GEOSAT Telemetry Processor

A working demonstration of modernizing flight-qualified legacy software
without breaking it, built for DAFITC.

The subject is `legacy/src/geosat.f`: 642 lines of fixed-form FORTRAN that
decode downlinked satellite telemetry. It is **synthetic** — written for this
demonstration so it can live in a public repository — but it is modeled on
real 1987-era ground software, and every pathology in it is one that occurs in
the field. It compiles. It runs. It is
in the critical path. Its author is gone, there is no design document, and the
maintainer field in the header reads `(VACANT)`.

That is the actual problem. Not "we have old code" — *we have old code that
works, that nobody understands, that we cannot stop running, and that we are
being asked to move.*

## What this repository demonstrates

**Comprehension happens inside the boundary.** The call graph over the legacy
deck is built by tree-sitter locally — parsing, not inference. Graphify does
have an optional semantic layer that calls a model; it is not used here, and
`make offline-proof` demonstrates that by blackholing all egress and stripping
every model API key before rebuilding. That default mode is a proxy-level
block rather than an air-gap; `tools/offline-proof.sh --airplane` powers the
interface down for the stronger claim.

**Behaviour is pinned before it is moved.** `legacy/tests/golden/` holds
telemetry frames and `legacy/tests/expected/` holds the bytes the 1987 binary
emits for them. The Python port in `modern/` is asserted byte-for-byte against
the real compiled binary, not against a description of it.

**The tests are proven able to fail.** A green suite is not evidence until it
has been shown to go red. `make mutants` introduces six real defects and
requires the suite to catch all six.

**The agentic loop is reviewable.** The workflows in `.github/workflows/*.md`
are GitHub Agentic Workflows (`gh-aw`). They run in Actions, their outputs are
constrained by `safe-outputs`, and the one that can write is fenced to
`docs/plans/**` and opens a draft pull request a human must approve.

## Quick start

```bash
make             # list the demo targets
make card        # one-page podium cheat sheet
make preflight   # check every dependency and name what is missing
make rehearse    # run every offline beat end to end
```

`make rehearse` exiting 0 is the guarantee that the offline portion of the
demo is reproducible.

## Layout

```
legacy/
  src/geosat.f          the 1987 deck -- one compilation unit, on purpose
  src/geosat.inc        COMMON block layout; most data flow goes through here
  tests/golden/         telemetry frames, hex
  tests/expected/       byte-exact output of the legacy binary
  graphify-out/         the knowledge graph, committed so CI can read it
modern/
  geosat_modern/        behaviour-preserving Python port, stdlib only
  tests/                characterization (byte parity) + unit tests
tools/
  preflight.sh          dependency check
  offline-proof.sh      rebuild the graph with egress blackholed
  rehearse.sh           full end-to-end regression gate
  mutation-check.sh     prove the suite can fail
  gen_frames.py         deterministic frame generator
.github/workflows/      three gh-aw agentic workflows
demo/
  DEMO-RUNBOOK.md       the stage script, verbatim
  CHEATSHEET.md         one page for the podium (`make card`)
  artifacts/            frozen outputs, the fallback for the live beat
```

## Why the legacy deck is a single file

Graphify resolves FORTRAN calls within a compilation unit. Split across nine
files, the graph came back with `geosat` as an isolated node — structurally
wrong and visibly broken. Merged, it resolves the full nine-edge call graph.
A single large deck is also closer to how 1987 ground software was actually
shipped. This is a real tool limitation, stated here rather than hidden.

## Defects preserved deliberately

These are not bugs to fix. They are behaviour the downstream archive loader
already depends on, and each is pinned by a test:

1. **Single-precision time overflow** in `ORBPRP`. Elapsed GPS seconds
   (~7.3e8) exceed binary32 precision, so the sub-satellite point does not
   change between frames four seconds apart.
2. **Stale leap-second constant** — `LEAP_SECONDS = 18`, last updated
   2016-12-31.
3. **Asterisk fill on numeric overflow.** FORTRAN's `F9.3` edit descriptor
   emits `*********` when a value will not fit. Python widens the field
   silently, so `modern/geosat_modern/fortran.py` reimplements the FORTRAN
   behaviour.
4. **Channel 8 and channel 11 share a byte.** Solar array angle is
   reconstructed from the low nibble of byte 28, which is also the low byte of
   payload temperature. Genuine wire-format coupling, per ECO 91-217.
5. **Frame counter reported stale on CRC failure.** `TLMDEC` returns before
   setting `FRMCNT`, so the error line prints the previous frame's counter.

Correcting any of these changes archived values. That is a mission decision,
not an engineering one, and it does not belong in a refactor.

## Requirements

- `gfortran` (`brew install gcc`)
- `python3` — stdlib only, no packages to install
- `graphify` (`uv tool install graphifyy`)
- `gh` with the `gh-aw` extension, for the live agentic beat only
