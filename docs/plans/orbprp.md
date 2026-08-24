# Modernization Plan: ORBPRP

## 1. Current behaviour

`ORBPRP` (`legacy/src/geosat.f:522-591`) computes a "quick look" subsatellite
point (SSP) from a frozen, circular-orbit element set. It is called once per
processed frame from the main driver (`geosat.f:78`), immediately after
`TIMCNV`, and writes its results into `COMMON /ORBBLK/` (`SSLAT`, `SSLON`,
`SSALT`, declared in `geosat.inc:52-53`), which `REPORT` (`geosat.f:599`)
formats into the `SSP LAT=... LON=... ALT=...` line (`geosat.f:635`,
format 903) consumed by the downstream archive loader by fixed column
position.

Per its own header comment (`geosat.f:511-521`), this is explicitly **not**
the operational ephemeris: it assumes a circular orbit at nominal altitude,
ignores J2, drag, and maneuver history, and its element set is frozen at GPS
epoch 630720000 (`geosat.f:535-543`) because "the element loader was never
ported off the VAX." The routine is documented as unsuitable for pointing or
conjunction products (memo GS-89-112).

Step by step (`geosat.f:556-588`):

- `A = RE + ELALT` — semi-major axis for a circular orbit at 785 km altitude
  (`geosat.f:556`).
- `PERIOD = 2*PI*SQRT(A**3/MU)` — Keplerian period, `MU = 398600.4418`
  (`geosat.f:558-559`).
- `DT = REAL(GSEC - ELEPOC)` — elapsed time since element epoch, **stored in
  single-precision `REAL`** (`geosat.f:527, 545, 561`). This is the load-
  bearing defect (see §2).
- `ARGLAT = AMOD(2*PI*DT/PERIOD, 2*PI)` — argument of latitude
  (`geosat.f:564-565`).
- `XLAT = ASIN(SIN(ELINC) * SIN(ARGLAT)) * 180/PI` — geodetic latitude of the
  SSP under the circular-orbit assumption (`geosat.f:567-570`).
- `LONASC = ELRAAN - RATE*DT`, `RATE = 360.985647/86400` — ascending node
  longitude, rotated for a fixed Earth-spin rate that ignores any leap-second
  or sidereal/solar distinction (`geosat.f:572-575`).
- `XLON = LONASC + ATAN2(COS(ELINC)*SIN(ARGLAT), COS(ARGLAT)) * 180/PI` —
  in-track displacement added to the node (`geosat.f:578-579`).
- Longitude is wrapped into `[-180, 180]` via one `AMOD` plus two conditional
  corrections (`geosat.f:582-584`), *not* a single normalized formula — this
  is a common FORTRAN idiom but is easy to get subtly wrong in a rewrite
  (e.g. mishandling exactly ±180 or the sign convention of `AMOD` with a
  negative operand).
- `SSALT` is always the constant `ELALT = 785.0`, never a computed altitude
  (`geosat.f:588`) — the routine's own name and the report label imply a
  propagated altitude, but it is actually just the frozen element restated.

All arithmetic is single-precision `REAL` throughout (`IMPLICIT NONE` plus
explicit `REAL` declarations, `geosat.f:523-554`), and all constants
(`PI`, `RE`, `ELALT`, `ELINC`, `ELRAAN`, `RATE`, `360.0`, `180.0`) are
single-precision literals or computed at that precision.

## 2. Preserved defects

- **Single-precision time overflow (primary defect).** `DT` is a 32-bit
  `REAL` holding `GSEC - ELEPOC` (`geosat.f:527, 545, 561`). Current GPS
  seconds are on the order of 7.3e8-1.4e9, which exceeds binary32's ~7
  significant decimal digits. The low-order bits of elapsed time — i.e. the
  sub-~100-second resolution — are silently discarded before any trig is
  applied. Consequence: **frames a few seconds apart propagate to the
  identical SSP** (confirmed in `modern/tests/test_units.py:130-141`,
  `OrbitTest.test_single_precision_defect_is_preserved`, and visible directly
  in the golden expected output, e.g. `legacy/tests/expected/pass01.out`
  lines 4-52 all read `LAT= 81.112 LON= 32.250` across four consecutive
  frames before the value steps). **If corrected** (e.g. by widening `DT` to
  double precision or restructuring the time arithmetic to preserve
  resolution), every archived SSP value computed from a `GSEC` this large
  would change — this is a silent, systemic re-baselining of an archived
  telemetry product, not a bug fix a ground-system maintainer is authorized
  to make unilaterally. **Pin as a test, do not fix.**

- **`SSALT` is not propagated.** `SSALT` is always the constant `ELALT`
  (`geosat.f:588`), regardless of `GSEC`. Any consumer treating the reported
  altitude as time-varying is being fed a constant. This is arguably a
  simplification consistent with "circular orbit, frozen elements" rather
  than a bug, but it must be preserved exactly (constant `785.0`) since the
  archive format has a dedicated `ALT=` field that downstream tooling may
  already treat as authoritative.

- **Frozen elements never update.** The element set (`ELALT`, `ELINC`,
  `ELRAAN`, `ELEPOC`) is a compile-time `PARAMETER` block, not loaded from
  input (`geosat.f:535-543`). This is explicitly documented as a known gap
  ("element loader was never ported off the VAX") rather than a defect to
  silently patch — any element update is an operational decision, not a
  code-modernization decision.

- **Earth rotation rate ignores UT1/leap-second corrections.** `RATE =
  360.985647/86400.0` (`geosat.f:574`) is a fixed sidereal-ish rate applied
  uniformly regardless of the actual UTC epoch, consistent with the
  "quick look, not for pointing" caveat. Preserve as-is; do not attempt to
  make it more astronomically correct.

## 3. Coverage gap

The four golden vectors (`legacy/tests/golden/{pass01,pass02,pass03,edge01}.tlm`)
exercise the following in `legacy/tests/expected/*.out`:

- Multiple frames at the same `GSEC`-derived `DT` window producing identical
  SSP (the single-precision defect, indirectly).
- SSP transitions between frames as `GSEC` advances further (e.g.
  `pass01.out` steps from `LAT=81.112/LON=32.250` to `LAT=79.621/LON=12.250`
  to `LAT=77.275/LON=-1.750`), which exercises the general propagation path
  and the ordinary (non-wrapping) branch of the longitude correction.

They do **not** exercise:

- **The longitude wrap boundary conditions.** No golden vector's `GSEC`
  produces a raw `XLON` that lands at or just past ±180° before wrapping
  (`geosat.f:582-584`), nor a case exercising the `AMOD` behavior for a
  *negative* `XLON` operand (FORTRAN `AMOD` result takes the sign of the
  first argument, so `AMOD` of a large negative longitude behaves
  differently from Python's `%`/`math.fmod` unless matched carefully — the
  modern port already uses `math.fmod` correctly per `orbit.py:101,124`, but
  no golden vector proves it). **New vector needed:** a frame whose `GSEC`
  yields `LONASC + in_track` computed to fall just outside `[-180, 180]`
  (e.g. arranged so `XLON` ≈ 180.5° or ≈ -180.5° before wrap), to pin the
  wrap-correction branch and its sign handling end-to-end through `REPORT`'s
  `F9.3` field.
- **The exact single-precision rounding of `DT` at a specific, documented
  `GSEC` value across the discretization boundary.** No golden vector is
  constructed to demonstrate *which* GSEC deltas collapse to the same binary32
  value versus which don't — the existing vectors show the effect
  incidentally but not at a chosen, reasoned boundary. **New vector needed:**
  two frames whose `GSEC` values are chosen so that one pair collapses to the
  same `DT` in binary32 and an adjacent pair (one second further) does not,
  to make the defect boundary itself a pinned, intentional characterization
  rather than an incidental one.
- **`SSALT` under any circumstance other than the constant.** No test
  distinguishes "always 785.0" from "computed but coincidentally equal to
  785.0 for these vectors." **New vector needed:** none strictly required
  functionally (the value never varies by construction), but a unit-level
  assertion (in the modern suite) that `SSALT`/`altitude_km` is exactly the
  `ELALT` parameter and independent of `GSEC` would close this gap without
  needing a new legacy golden frame.
- **`ARGLAT` wrap via `AMOD` for `U` values spanning multiple full
  revolutions** (i.e. `DT` large enough that `U` is several multiples of
  `2*PI`). None of the golden `GSEC` values are far enough past
  `ELEPOC = 630720000` relative to the ~100-minute period to be checked at a
  chosen large multiple; the existing vectors happen to land within the
  first few periods only by accident of using near-epoch GPS times.

## 4. Incremental steps

Each step is reviewable and revertible independently; none combines a port
with a behaviour change; the full characterization suite
(`modern/tests/test_characterization.py`) and unit suite
(`modern/tests/test_units.py`) must stay green after every step.

1. **Add the two missing golden vectors** (longitude-wrap boundary case and
   the single-precision `DT` collapse-boundary case) to
   `legacy/tests/golden/`, generate their expected output by running the
   *existing, unmodified* legacy binary, and commit the pair
   (`.tlm` input + `.out` expected) to `legacy/tests/expected/`. No source
   changes in this step.
2. **Add the corresponding modern unit assertions** in
   `modern/tests/test_units.py` (`OrbitTest`) that pin: (a) `SSALT`/
   `altitude_km` is always exactly `ELALT` regardless of `GSEC`, and (b) the
   `ARGLAT` wrap is correct for a `GSEC` several periods past `ELEPOC`. No
   changes to `modern/geosat_modern/orbit.py` in this step — these tests
   should already pass against the current port, since the port already
   claims to replicate the behaviour; the step's purpose is to make the
   claim checkable.
3. **Register the two new vectors** in `VECTORS` inside
   `modern/tests/test_characterization.py` so they run through the
   byte-for-byte legacy-vs-modern parity harness. This is purely wiring, not
   a behaviour change, and should pass immediately given step 1's output was
   generated from the same legacy binary the harness builds.
4. **Document the preserved defects inline**, if not already fully covered,
   by extending code comments (not logic) in `modern/geosat_modern/orbit.py`
   to reference the specific new pinned tests by name, so a future reader
   sees "defect X is pinned by test Y" rather than having to rediscover it.
   No arithmetic changes.

No step in this plan proposes changing `ORBPRP`'s numerical behaviour,
`geosat.inc`'s COMMON layout, or the `REPORT` format statements. This plan
is characterization-only.

## 5. Proof obligation per step

- **Step 1:** `python -m unittest modern.tests.test_characterization` must
  still pass for the four existing vectors (unaffected), and the newly
  committed `.out` files must be byte-identical to what
  `legacy/build/geosat` emits for the new `.tlm` inputs — verified by
  running the built legacy binary against the new input and diffing against
  the committed expected file before commit (this is a one-time generation
  step, not an ongoing test in itself; the ongoing proof is step 3).
- **Step 2:** the two new/extended cases in
  `modern/tests/test_units.py::OrbitTest` pass under
  `python -m unittest modern.tests.test_units`.
- **Step 3:** `python -m unittest modern.tests.test_characterization` passes
  with `VECTORS` including the two new names, i.e.
  `CharacterizationTest` reports byte-for-byte parity for all six vectors,
  not four.
- **Step 4:** no automated proof beyond "the full suite from steps 1-3 still
  passes unchanged" — this step is comment-only and is proven by absence of
  any diff to test results.

Naming: the tests above already exist or are named explicitly; "verify
correctness" is never the sole proof for any step.

## 6. Explicitly out of scope

- Any change to `ORBPRP`'s arithmetic, precision, or element set.
- Any change to `geosat.inc` COMMON block layout (`/ORBBLK/` or otherwise).
- Any change to `REPORT`'s format statements or column positions — the
  archive loader's fixed-column contract is untouched.
- Fixing the single-precision `DT` defect, the frozen-element-set gap, or
  the non-propagated `SSALT` — these are flagged for a human mission-
  assurance decision, not silently corrected here.
- Any change to `TIMCNV`, `ENGCNV`, `LIMCHK`, or any other routine in the
  deck.
- Performance, style, or structural refactoring of `modern/geosat_modern/orbit.py`
  beyond the comment addition in step 4.
- Extending `orbit.py` or `ORBPRP` to consume a real, updatable element set.

## 7. Open questions for a human

- Should the single-precision `DT` truncation defect ever be corrected, and
  if so, is a coordinated archive re-baseline (recomputing historical SSP
  values) acceptable, or must the defect be preserved indefinitely for
  archive continuity?
- Is the frozen, non-updatable element set (`ELALT`/`ELINC`/`ELRAAN`/
  `ELEPOC`) an accepted permanent limitation of the quick-look product, or
  is there an intent to eventually port an element loader — and if so, does
  that change the archive schema (currently one static altitude value)?
- Given `ORBPRP`'s own documented caveat that it must not be used for
  pointing or conjunction products, should the archive record explicitly
  flag SSP values as "quick-look only," and if so, is that a format change
  requiring downstream archive-loader coordination (out of scope for this
  plan, but worth flagging)?
