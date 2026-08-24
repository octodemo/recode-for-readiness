# Modernization Plan: `ORBPRP`

Scope: `SUBROUTINE ORBPRP(GSEC)` in `legacy/src/geosat.f:522-591`, and its
already-drafted port at `modern/src/orbit.rs`. This routine writes
`SSLAT`, `SSLON`, `SSALT` into COMMON `/ORBBLK/` (`legacy/src/geosat.inc`),
which is read only by `REPORT` (`geosat.f:599`) to print the `SSP LAT=...
LON=... ALT=...` line that the downstream archive loader (ARCLOD) parses
by fixed column position.

## 1. Current behaviour

`ORBPRP` is a "quick look" circular-orbit propagator with a frozen element
set (`geosat.f:535-543`): altitude 785.0 km, inclination 98.6°, RAAN
142.35°, epoch GPS second 630720000. No elements are ever reloaded; the
header comment (`geosat.f:519-520`) says the element loader was never
ported off the VAX.

Per call, given `GSEC` (the frame's GPS seconds, `geosat.f:527,561`,
supplied by the caller from `TIMCNV`'s output at `geosat.f:78` in the main
driver):

- `A = RE + ELALT` (`geosat.f:556`); `PERIOD` from Kepler's third law with
  `MU = 398600.4418` (`geosat.f:559`).
- `DT = REAL(GSEC - ELEPOC)` (`geosat.f:561`) — the integer difference is
  cast to a 32-bit `REAL`, not carried in double or integer precision.
- `ARGLAT = AMOD(2*PI*DT/PERIOD, 2*PI)` (`geosat.f:564-565`) — a purely
  linear argument-of-latitude model; no eccentricity, no J2, no drag.
- `XLAT = ASIN(SIN(INC)*SIN(ARGLAT)) * 180/PI` (`geosat.f:570`).
- `LONASC = ELRAAN - (360.985647/86400)*DT` (`geosat.f:574-575`) — a
  constant sidereal-rotation-rate correction applied to raw `DT`, with no
  wrap before use.
- `XLON = LONASC + ATAN2(COS(INC)*SIN(ARGLAT), COS(ARGLAT))*180/PI`, then
  wrapped to `[-180, 180]` with one `AMOD(., 360)` plus two conditional
  corrections (`geosat.f:578-584`).
- Results are stored unconditionally into `SSLAT`, `SSLON`, `SSALT =
  ELALT` (`geosat.f:586-588`) on every call, regardless of whether the
  frame that produced `GSEC` was otherwise valid.

`ORBPRP` communicates only through COMMON, not through return value or
`INTENT(OUT)` argument, so any future change to call ordering in the main
driver (`geosat.f:78`) that ran `REPORT` before `ORBPRP` for a given frame
would silently print stale coordinates with no error indication.

**Bug-shaped things, called out explicitly:**

- **Single-precision `DT` (`geosat.f:561`).** For current-epoch GPS seconds
  (roughly 1.3–1.4 billion), `GSEC - ELEPOC` is itself on the order of
  7×10^8, which exceeds the ~7 significant decimal digits binary32
  carries. The subtraction result loses low-order seconds of resolution,
  so the propagated point is coarse-quantized in time; frames only a few
  seconds apart can propagate to bit-identical `SSLAT`/`SSLON`. This is
  already documented and pinned in `modern/src/orbit.rs`'s "KNOWN DEFECT"
  block and in `modern/tests/units.rs::single_precision_defect_is_preserved`.
- **No real ephemeris.** The header explicitly warns this routine must
  never be used for pointing or conjunction products (`geosat.f:513-517`,
  memo GS-89-112), yet nothing in the code enforces that; a consumer
  reading only the archived output has no way to know the SSP is "quick
  look" data rather than precision ephemeris.
- **Asymmetric wrap order.** `LONASC` is never wrapped on its own; only
  the final sum of `LONASC + in_track` is wrapped (`geosat.f:578-584`).
  This is part of the pinned numeric contract, not incidental style —
  reordering it changes results near ±180°.
- **Platform-dependent transcendentals.** Single-precision `SIN`/`COS`/
  `ASIN`/`ATAN2` mean the legacy binary's libm resolution is part of the
  archived numeric contract, as `modern/src/precision.rs` documents in
  detail (byte parity against the compiled deck is an empirical, pinned
  result, not a language guarantee).

## 2. Preserved defects

None of the following should be fixed in this pass. Each becomes a pinned
characterization/unit test, not a correction.

1. **Single-precision `DT` overflow of resolution** (`geosat.f:561`;
   already pinned by `modern/tests/units.rs::single_precision_defect_is_preserved`).
   Correcting it (e.g. computing `DT` in `f64`/`i64`) would change
   `SSLAT`/`SSLON` for essentially every archived frame at current
   epochs — a mission-assurance decision, not a refactor.
2. **Frozen elements, no ephemeris refresh** (`geosat.f:519-520,535-543`).
   "Fixing" this by loading real elements would change every archived SSP
   and violate memo GS-89-112's explicit prohibition on this routine
   being used for pointing — i.e. it is deliberately wrong-but-cheap, and
   downstream tooling may already assume that.
3. **Unconditional COMMON overwrite regardless of upstream frame
   validity** (`geosat.f:586-588`). If a caller reordering, or a
   partial/garbage `GSEC`, ever caused `ORBPRP` to run on a bad frame,
   `REPORT` would still print a plausible-looking SSP with no error
   indication. Preserving this (not adding validation) keeps output
   byte-identical for the golden vectors; adding validation later is a
   behaviour change, out of scope here.
4. **No wrap of `LONASC` before summing with `in_track`**
   (`geosat.f:574-575,578`) — only the final sum is wrapped. Reordering
   the wrap changes numeric output near boundary cases and must not
   happen inside a pure porting step.

## 3. Coverage gap

`legacy/tests/golden/` currently exercises:
- `pass01/02/03.tlm`: nominal frames, each producing a distinct SSP over
  the course of a pass, confirming the propagator advances with time.
- `edge01.tlm`: 5 frames (frame counters 900000–900004 per
  `legacy/tests/expected/edge01.out`), all of which yield the identical
  `SSP LAT= 81.112 LON= 32.250 ALT= 785.0`. This is the single-precision
  DT-quantization defect appearing in the golden set, but only
  implicitly — nothing in the vector or its expected output states that
  this repetition is a *required* property rather than coincidence.

**Gaps not currently exercised by any golden vector:**

- **No vector pins the exact DT-quantization boundary as a stated
  property.** No `.tlm`/`.out` pair exists at a *current* epoch with two
  frames 4 seconds apart that are asserted to collapse to the same SSP
  (mirroring what `single_precision_defect_is_preserved` checks in Rust
  at GPS seconds 1356998418/1356998422). Such a vector would need two
  frames whose `GPSSEC` fields (decoded per `TIMCNV`) differ by exactly 4
  at that epoch, with everything else in the frame held constant, and an
  expected `.out` where both `SSP` lines are byte-identical.
- **No vector exercises the longitude-wrap boundary.** None of the
  existing vectors drive `XLON` to land at or just past ±180° before the
  correction branches at `geosat.f:583-584` fire. A new vector would need
  `GSEC` values hand-solved against the propagator so that
  `LONASC + in_track` crosses +180 in one frame and -180 in another,
  confirming both correction branches independently.
- **No vector exercises `GSEC` before `ELEPOC` (negative `DT`).** All
  golden frames post-date epoch 630720000. A vector with GPS seconds less
  than that would confirm FORTRAN `AMOD`'s sign-preserving behaviour
  (unlike Python's `%`) is correctly reproduced by `fmod` in
  `precision.rs` for negative arguments.
- **No vector isolates `ORBPRP`'s inputs from the rest of the frame.**
  Every existing vector varies raw telemetry counts and `GSEC` together,
  so a diff against a future change to this routine alone is not directly
  readable from the golden output; a vector holding raw counts fixed
  while varying only `GSEC` across frames would make such a diff trivial.

## 4. Incremental steps

Every step below must leave the characterization suite
(`modern/tests/characterization.rs`) and the existing `ORBPRP`-adjacent
unit tests green, and preserves current byte-for-byte output.

1. **Add the missing golden vectors** (current-epoch DT-quantization
   pair, longitude-wrap boundary pair, pre-epoch negative-`DT` frame) as
   new files under `legacy/tests/golden/*.tlm`, with corresponding
   `legacy/tests/expected/*.out` generated by running the *compiled
   legacy binary* against them (never hand-computed), and register the
   new vector names in `characterization.rs::VECTORS`. This is pure
   test-data addition; no change to `geosat.f`, `geosat.inc`, or
   `orbit.rs`.
2. **Add matching unit tests in `modern/tests/units.rs`** for the
   longitude-wrap and negative-`DT` cases, calling `propagate()` directly
   with the same GPS seconds as the new vectors in step 1, asserting
   against the values captured from the legacy binary's output. Test-only
   change.
3. **Add an explicit test for `AMOD` sign semantics** on
   `modern/src/precision.rs::fmod`, e.g. asserting `fmod(-x, 2*PI)`
   matches the sign-preserving FORTRAN `AMOD` result rather than an
   always-positive modulo, using the pre-epoch vector from step 1 as the
   oracle for expected sign/magnitude. Test-only change.
4. Only after 1–3 are green: **open a separate follow-up plan**,
   explicitly flagged as out of scope for this PR, addressing whether the
   single-precision `DT` defect and the frozen-element-set behaviour
   should ever be corrected, and under what versioned/flagged mechanism
   the archive loader would distinguish pre- and post-correction SSP
   values. This plan does not authorize that work; it only names it so it
   is not lost.

No step in this list modifies `geosat.f`, `geosat.inc`, or `orbit.rs`.

## 5. Proof obligation per step

- **Step 1**: `cargo test --test characterization` passes with the new
  vector names added to `VECTORS`. The harness already refuses to pass
  without building and running the real legacy binary as the oracle, so
  a green run is proof the new fixtures are consistent with the legacy
  deck, not merely plausible-looking.
- **Step 2**: the new `#[test]` functions in `modern/tests/units.rs` pass,
  each asserting the exact `latitude_deg`/`longitude_deg` captured from
  the legacy-binary run in step 1 — e.g.
  `longitude_wrap_boundary_matches_legacy` and
  `negative_dt_before_epoch_matches_legacy` (naming the test is the
  proof).
- **Step 3**: the new `#[test]` for `fmod` sign semantics passes, using
  the legacy-binary-derived expected value from the pre-epoch vector as
  the oracle (not just comparing against Rust's own `%` operator in
  isolation, which would only prove internal self-consistency).
- **Step 4**: not proven by a test — it is scoped as a decision document;
  the proof obligation is explicit human sign-off, tracked under Open
  Questions below.

## 6. Explicitly out of scope

- Any change to `DT`'s precision, the frozen element set, the
  propagation model (circular, no J2/drag), or the wrap order of
  `LONASC` vs. `in_track`.
- Any change to `geosat.f`, `geosat.inc`, `modern/src/orbit.rs`, or any
  existing test file — this task is documentation-only.
- `REPORT`'s formatting of the `SSP` line (`geosat.f:599` onward) —
  column layout is a separate concern with its own preserved-defect
  surface (see `modern/src/fortran.rs`'s asterisk-fill behaviour) and is
  not touched here.
- `TIMCNV`, `ENGCNV`, `LIMCHK`, `TLMDEC` — upstream of `ORBPRP`, each with
  its own COMMON-block coupling, out of scope for this plan.
- Any runtime validation of `GSEC` or rejection of stale/invalid frames
  before propagation — named in Preserved Defect #3 as a candidate future
  behaviour change, not something to add now.

## 7. Open questions for a human

1. Should the single-precision `DT` truncation ever be corrected, and if
   so, does the archive loader need a schema/version field to distinguish
   pre- and post-correction SSP values already on file? This plan does
   not decide that; it only names it (Preserved Defect #1).
2. Is it acceptable to keep archiving "quick look" (non-ephemeris) SSP
   values indefinitely, or should there be a parallel channel/flag
   marking these records as not-for-pointing-use, given that memo
   GS-89-112's warning is currently enforced only by a source comment?
   If a flag is added, is that a change to `REPORT`'s fixed-column format
   (breaking the archive contract) or a new field appended at end of
   line (non-breaking)? That format decision is a human, mission-
   assurance call.
3. Should the frozen orbital elements (altitude/inclination/RAAN/epoch)
   ever be refreshed from a real element set, and who owns validating
   that against the FDF's precision ephemeris before such a change is
   even considered?
4. Is adding new golden vectors (step 1) within the spirit of "do not
   modify the legacy deck, the modern package, or any test"? This plan
   treats new `.tlm`/`.out` fixture files as test *data*, not the deck
   itself or existing tests (`legacy/src/geosat.f` and all current test
   files remain untouched), but a human should confirm that reading
   before step 1 is executed.
