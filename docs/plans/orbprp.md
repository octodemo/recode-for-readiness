# Modernization Plan: ORBPRP

`ORBPRP` (`legacy/src/geosat.f:522`) is the "quick look" subsatellite-point
(SSP) propagator. It is called once per good frame from the main driver
(`geosat.f:78`, confirmed by `legacy/graphify-out/graph.json` edge
`src_geosat_geosat -> src_geosat_orbprp`, relation `calls`, `L78`), after
`TIMCNV` and before `REPORT`. Its outputs (`SSLAT`, `SSLON`, `SSALT` in
COMMON `/ORBBLK/`, `geosat.inc`) are consumed only by `REPORT`
(`geosat.f:599`), which writes them at fixed columns
(`903 FORMAT ('SSP LAT=', F8.3, '  LON=', F9.3, '  ALT=', F7.1)`,
`geosat.f:637`) into the archive-loader-parsed pass log. A modern Rust port
already exists at `modern/src/orbit.rs` (`propagate()`), with characterization
coverage in `modern/tests/units.rs`. This plan only covers verifying and
hardening that existing port against the legacy deck; it proposes no new
production code changes beyond what's listed under "Incremental steps."

## 1. Current behaviour

All elements are frozen constants, "epoch GPS second 630720000," because
"the element loader was never ported off the VAX" (`geosat.f:519-520,
535-543`). The routine:

- Computes semi-major axis `A = RE + ELALT` (`geosat.f:556`) and Keplerian
  period `PERIOD = 2*PI*SQRT(A**3/MU)` with `MU = 398600.4418`
  (`geosat.f:558-559`).
- Computes `DT = REAL(GSEC - ELEPOC)` — **an integer difference cast down
  into a 32-bit `REAL` (`geosat.f:561`)**. `GSEC` is `INTEGER` GPS seconds
  from `TIMCNV`. For any realistic post-1990s epoch, `DT` is on the order of
  7×10⁸, which exceeds the ~7 significant decimal digits of IEEE-754
  binary32. The low-order seconds of `DT` are rounded away.
- Derives argument of latitude `U = 2*PI*(DT/PERIOD)`, wrapped with
  `AMOD(U, 2*PI)` (`geosat.f:564-565`).
- Derives geodetic latitude via `ASIN(SINI*SIN(ARGLAT))` (`geosat.f:570`) —
  this ignores Earth oblateness/J2 and any inclination-dependent latitude
  correction; it is explicitly documented as circular-orbit-only
  (`geosat.f:513-517`).
- Derives longitude of ascending node by rotating for Earth spin at a fixed
  rate `360.985647/86400.0` deg/s applied to the *single-precision, already
  info-lossy* `DT` (`geosat.f:572-575`), then adds an in-track term via
  `ATAN2` (`geosat.f:578-579`), then wraps to `[-180, 180]`
  (`geosat.f:582-584`).
- Writes `SSLAT`, `SSLON`, `SSALT = ELALT` (constant, never actually
  propagated) into COMMON (`geosat.f:586-588`).

**Bug-shaped behaviour, called out because it is load-bearing:**

- `DT`'s single-precision cast (`geosat.f:561`) causes the propagated SSP to
  go *stale* — it stops changing — once `GSEC - ELEPOC` grows large enough
  that consecutive frames' GPS-second deltas fall below binary32's
  representable resolution at that magnitude. This is directly visible in
  the golden vectors: e.g. `pass01.out` frames 1–4 (lines 4/20/36/52) all
  report identical `SSP LAT= 81.112  LON= 32.250`, and only "jump" every few
  frames rather than every frame — this is not orbital dynamics, it's
  precision loss in `DT`.
- `SSALT` is never actually computed from the propagation — it's just the
  constant `ELALT = 785.0` (`geosat.f:588`), so "ALT=" in the archive is
  always exactly 785.0 regardless of anything else. This looks like a
  placeholder that was never finished, but the archive has always recorded
  it this way.
- The elements are frozen at a fixed 1990-2000-era epoch and were "never
  ported off the VAX" (`geosat.f:519-520`) — the routine silently produces a
  plausible-looking but numerically meaningless SSP for any telemetry frame,
  regardless of the spacecraft's real orbit today. Nothing in `ORBPRP`
  detects or flags this; `REPORT` prints it unconditionally as if it were
  current.

## 2. Preserved defects

These are wrong, but downstream-load-bearing, and must be pinned rather than
fixed in this pass:

1. **Single-precision `DT` truncation / SSP staleness** (`geosat.f:561`).
   Fixing this (e.g. computing `DT` in double precision, or decomposing the
   subtraction to avoid catastrophic cancellation) would change `SSLAT`/
   `SSLON` on every frame where the archive currently shows a stale,
   repeated value. Every historical archive record's SSP would change if
   this were "corrected" — this is exactly the class of change the
   constraint in this task forbids doing implicitly. The modern port in
   `modern/src/orbit.rs:14-26` already documents this explicitly and
   reproduces it in `f32`; `modern/tests/units.rs:183-189`
   (`single_precision_defect_is_preserved`) already pins it. No code change
   needed here — just confirm the pin holds (see Coverage gap below).
2. **`SSALT` is a constant, not a propagated altitude** (`geosat.f:588`,
   `modern/src/orbit.rs:103`). The archive format reserves a column for
   altitude but it has never varied. Any downstream consumer that treats
   "ALT=" as a live propagated value is already relying on a value that has
   never moved. Changing this to a real altitude computation would be the
   first archive record in the pass log ever to show a non-785.0 altitude,
   which is a discontinuity a downstream loader/analyst may not expect.
3. **Frozen orbital elements at a fixed historical epoch**
   (`geosat.f:535-543`). The routine will keep producing an SSP consistent
   with a `785.0`-altitude, `98.6`-degree-inclination orbit at RAAN `142.35`
   forever, regardless of true spacecraft state. This is a known, documented
   limitation (`geosat.f:513-520`) rather than a silent bug, but it's still
   preserved behaviour: nothing in the deck or the modern port re-loads
   elements, and this plan does not add an element loader.

## 3. Coverage gap

The golden vectors (`legacy/tests/golden/*.tlm` → `legacy/tests/expected/*.out`)
exercise realistic frame sequences and *do* show the staleness pattern in
aggregate (SSP repeats across several consecutive frames, then jumps), but:

- **No golden vector isolates the `DT` truncation boundary.** All four
  golden files use small, closely-spaced `GPSSEC` values encoded in the
  frames (inferred from repeated multi-frame SSP blocks); none demonstrably
  probes the boundary where two consecutive real GPS-second values (4
  seconds apart, matching the actual telemetry cadence) collapse to the
  *same* binary32 `DT` yet fall on opposite sides of a `PERIOD`-relative
  wrap in `ARGLAT` (i.e., where staleness could plausibly *not* hold at some
  epoch). A new golden vector should encode two consecutive frames whose
  `GPSSEC` values are 4 seconds apart at a *known* large epoch (e.g. current
  real-world GPS seconds, ~1.4×10⁹) with UTC/telemetry fields otherwise
  identical to an existing pass file, so that `SSP LAT=`/`LON=` in the
  expected output can be asserted equal by construction, not just observed
  as equal empirically as in the existing files.
- **No golden vector demonstrates `SSALT` staying constant across an
  otherwise-changing SSP.** Existing vectors always show `ALT=  785.0`, but
  because that's the *only* value ever produced, the golden files don't
  distinguish "correctly reproduced constant" from "coincidentally always
  785.0 because no other value was ever exercised." A vector is only useful
  here if paired with a (currently nonexistent) alternate frozen-element set
  — out of scope for this plan; note only as a gap.
- **No golden vector exercises the negative-`ARGLAT`/southern-latitude or
  longitude-wrap-at-exactly-±180 boundary.** All existing expected outputs
  show latitudes in `16.6`–`81.1` (all positive) and longitudes that never
  land exactly on `±180.0`. The `XLON .GT. 180.0` / `XLON .LT. -180.0`
  branches (`geosat.f:583-584`) are therefore not proven exercised by the
  golden set. A new vector would need a `GPSSEC` chosen so that
  `LONASC + in-track term` computed from the frozen elements crosses `180`
  degrees before wrapping, and/or `ARGLAT` in the third/fourth quadrant so
  `ASIN` returns a negative latitude.
- `modern/tests/units.rs` covers the staleness defect
  (`single_precision_defect_is_preserved`) and longitude wrap range
  (`longitude_is_wrapped`) as unit-level pins on `propagate()` directly, but
  neither is cross-checked against a legacy-deck-produced fixed-point value
  (i.e., no test asserts `propagate(exact_gsec) == (known F8.3/F9.3/F7.1
  legacy output)` parsed from `legacy/tests/expected/*.out`). That
  cross-check is the actual equivalence proof this constraint demands and is
  currently missing.

## 4. Incremental steps

Every step below is independently reviewable and revertible, and the
existing characterization suite (`legacy` golden pass/fail plus
`modern/tests/characterization.rs` and `modern/tests/units.rs`) must stay
green after each one. No step changes numerical behaviour.

1. **Add a legacy-value cross-check test.** In `modern/tests/units.rs` (or a
   new `orbit_parity.rs`), parse the `SSP LAT=/LON=/ALT=` fields out of
   `legacy/tests/expected/pass01.out` (and the other three `.out` files) for
   at least one frame per file, decode the matching frame's `GPSSEC` from
   the corresponding `.tlm` golden input (via the existing frame-decode
   path already used by `modern/tests/characterization.rs`), call
   `orbit::propagate` on that `GPSSEC`, and assert the formatted output
   matches the legacy `F8.3/F9.3/F7.1` fields exactly. This is pure test
   addition — no production code changes.
2. **Add the boundary golden vector** described in Coverage gap item 1: a
   new `legacy/tests/golden/orbprp_dt_boundary.tlm` (or an extra pair of
   frames appended to a copy of an existing file, if the harness expects
   fixed file names — confirm the test runner's file-discovery convention
   in `modern/tests/characterization.rs` before naming) plus its generated
   `legacy/tests/expected/orbprp_dt_boundary.out`, produced by running the
   *existing, unmodified* `legacy/src/geosat.f` binary against the new input
   (not by hand-computing expected values) so the expected file is
   authoritative legacy output, not a guess. This step touches only
   `legacy/tests/golden/` and `legacy/tests/expected/` — new files, not
   modifications to existing ones — plus a matching test file in
   `modern/tests/` that decodes and checks it.
3. **Add the longitude/latitude-sign boundary golden vector** described in
   Coverage gap item 3, following the same process as step 2: construct
   frame(s), run the legacy binary to produce the expected file, add a
   corresponding modern-side assertion.
4. **Document the `SSALT` constant-output defect explicitly as a pinned
   test**, mirroring the existing `single_precision_defect_is_preserved`
   pattern: add a `modern/tests/units.rs` test asserting
   `propagate(x).altitude_km == ELEMENT_ALTITUDE_KM` for at least two very
   different `x`, with a comment referencing this plan and
   `geosat.f:588`, so a future contributor sees it is pinned deliberately,
   not merely untested.

No step in this plan modifies `legacy/src/geosat.f`, `legacy/src/geosat.inc`,
`modern/src/orbit.rs`, or any existing test. All work is additive: new golden
fixtures and new characterization/unit tests.

## 5. Proof obligation per step

1. `cargo test --test units` (or the crate's full test command) passes,
   including the new cross-check test, which fails loudly (assertion
   mismatch, printed legacy vs. modern values) if `orbit::propagate` ever
   diverges from a legacy-produced fixed-point value.
2. The legacy build (`legacy/Makefile`, `make && ./build/geosat <
   tests/golden/orbprp_dt_boundary.tlm`) reproduces the checked-in expected
   file byte-for-byte (`diff` returns no output) — this is the proof the new
   fixture is legacy-truth, not hand-crafted. Then the modern-side test
   added in step 2 passes against that same fixture.
3. Same proof shape as step 2, for the new sign/wrap fixture.
4. `cargo test --test units` passes with the new `SSALT` pin present, and
   the test name/comment is reviewable evidence that the constant-altitude
   defect is a recorded, intentional pin (not an oversight) per this plan's
   section 2.

## 6. Explicitly out of scope

- Any change to the numerical output of `ORBPRP` or `orbit::propagate` —
  including "fixing" the single-precision `DT` truncation, computing a real
  `SSALT`, or reloading orbital elements from a live source. All three are
  documented, archive-affecting behaviour changes and are not touched here.
- Any change to `REPORT`'s format strings or column layout
  (`geosat.f:632-640`) — explicitly flagged in the deck as consumed by the
  downstream archive loader by fixed column position.
- Any change to `legacy/src/geosat.f` or `legacy/src/geosat.inc` — this plan
  only adds test fixtures alongside the existing golden/expected directories
  and adds tests in `modern/tests/`.
- Any change to `modern/src/orbit.rs` itself — the existing port already
  matches the legacy algorithm term-for-term and already documents the
  known defect; this plan only strengthens the proof that it matches,
  it does not alter the port.
- Element-loader modernization (loading current orbital elements instead of
  the frozen 1990s-epoch constants) — explicitly noted in the deck
  (`geosat.f:519-520`) as unfinished work, but out of scope for a
  characterization-and-port-verification pass.

## 7. Open questions for a human

1. Should the new golden fixtures (steps 2–3) use a `GPSSEC` near the
   *current* real epoch (to make the staleness defect maximally visible and
   relevant to today's operations), or should they stay within the range of
   epochs already represented in the existing golden set, to minimize the
   chance of exposing an unrelated, currently-undetected defect at a
   never-before-exercised input? This is a test-design decision with
   mission-assurance implications and should not be made unilaterally.
2. If step 2's new fixture reveals that the legacy binary's actual staleness
   *window width* (how many consecutive 4-second frames repeat the same SSP
   before jumping) differs from what's currently assumed from the existing
   golden files, does that change belong in this plan's "preserved defects"
   list, or does it warrant its own mission-assurance review before being
   pinned as permanent test truth?
3. Is there an appetite, on a separate and explicitly approved track, to
   eventually correct the `SSALT` constant-output defect and/or the `DT`
   truncation — and if so, does correcting either require notifying or
   coordinating with the downstream archive loader's owning team before any
   such change ships, given every historical value would remain unchanged
   but all *future* values would shift? This plan takes no position; it only
   flags that the decision is not an engineering one alone.
4. Confirm whether `legacy/tests/golden`/`legacy/tests/expected` are
   considered append-only fixtures that any contributor may extend, or
   whether new golden vectors require sign-off from whoever owns the
   characterization suite (there is no listed maintainer for `geosat.f` —
   "MAINTAINED BY: (VACANT)" per the file header) before being added.
