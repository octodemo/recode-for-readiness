# Modernization Plan: TIMCNV

## Current behaviour

`TIMCNV` (`geosat.f:440-509`) converts GPS seconds-of-epoch (`GSEC`, an
`INTEGER`, i.e. a 32-bit signed Fortran default integer under the build's
`-std=legacy` flags) into UTC calendar fields stored in `/TIMBLK/`
(`UTCYR, UTCMON, UTCDAY, UTCHR, UTCMIN, UTCSEC, UTCDOY`).

1. **Leap second subtraction** (`geosat.f:462`): `TOTSEC = GSEC - LEAPS`,
   where `LEAPS = 18` is a hand-maintained `DATA` constant
   (`geosat.f:447-448`), last updated 2016-12-31 per the header comment
   (`geosat.f:433`). This is a static offset, not a leap-second table lookup.

2. **Day/time-of-day split** (`geosat.f:464-469`): integer division
   `NDAYS = TOTSEC / 86400` truncates toward zero (Fortran semantics), and
   `REM` is corrected by a manual floor-adjustment (`IF (REM .LT. 0)`) rather
   than a true floored division. For all inputs actually seen in the golden
   vectors and expected mission use (`GSEC` post-epoch, `TOTSEC >= 0`), this
   is equivalent to floored division and produces `REM` in `[0, 86400)`.

3. **HH:MM:SS decomposition** (`geosat.f:471-473`): straightforward, no
   surprises.

4. **Epoch walk-forward** (`geosat.f:476-486`): year is walked forward one at
   a time from 1980, with `NDAYS` offset by `+5` (`geosat.f:477`) to account
   for the GPS epoch being January 6th, not January 1st. Leap year test at
   `geosat.f:481-482` is the standard Gregorian rule (divisible by 4, not by
   100 unless also by 400) — correct.

5. **Day-of-year and month/day decomposition** (`geosat.f:488-506`):
   `UTCDOY = NDAYS + 1` computed *before* the month loop consumes `NDAYS`
   (`geosat.f:490` vs. `geosat.f:500`), so day-of-year is correct and
   independent of the subsequent month walk. Month walk at `geosat.f:492-502`
   uses the same per-year leap test duplicated inline (`geosat.f:495-497`)
   rather than a shared leap-year function — a maintenance smell, not a bug.

**Things that look like bugs, and are:**

- **No `LEAPS` update since 2016-12-31** (`geosat.f:432-433`, `447-448`).
  Real leap seconds inserted after that date are silently absorbed into the
  UTC field values as a 1-second (per event) skew. This is explicitly called
  out in the source comment as a known, hand-maintained liability, not an
  oversight introduced by this port.
- **No overflow/range guard on `GSEC`.** If `GSEC` is negative enough that
  `TOTSEC < -5*86400` (i.e. before the epoch adjustment window), the
  walk-forward loop at `geosat.f:479-486` will not terminate correctly for
  the intended range and no negative-year handling exists. Not currently
  reachable from the golden vectors (see Coverage gap).
- **Two-digit vs four-digit year ambiguity, explicitly parked.** The 1998
  Y2K patch comment (`geosat.f:435-438`) states `UTCYR` is the *full* 4-digit
  year and that a "strip chart recorder driver" (`RTDISP`, referenced only
  in comment, not present in this repository) elsewhere depends on a
  two-digit year *also* being derivable from `/TIMBLK/`. No 2-digit field
  exists in `/TIMBLK/` today (`geosat.inc:45-46`); the comment is a landmine
  warning for anyone who touches this common block, not a currently active
  defect in `TIMCNV` itself. Flagged here because any modernization touching
  `/TIMBLK/` layout must account for it.

## Preserved defects

These are wrong (by a modern reading) but load-bearing for archive
byte-identical output, and must become pinned characterization tests, not
fixes:

1. **Frozen `LEAPS = 18`.** Fixing this to use a current/maintained leap
   second table would shift every `UTCHR/UTCMIN/UTCSEC` value computed from
   any `GSEC` after the next real leap-second insertion — changing archived
   values the downstream loader has already ingested by fixed column
   position for the mission-to-date. **Preserve as-is; do not source from a
   live table in this port.**
2. **Truncating-division-plus-manual-floor-correction** for `NDAYS`/`REM`
   instead of true floored division. Behaviourally equivalent to floor
   division for all non-negative `TOTSEC`, which is all real telemetry to
   date, but a literal recode using a language's native floor-division
   operator must be verified equivalent over the actual observed range, not
   assumed identical for out-of-range/negative inputs.
3. **`+5` day epoch-offset magic number** (`geosat.f:477`) — correct only
   because it is paired with `YR = 1980` as the starting year and the walk
   loop's leap-year test. Any refactor that changes the loop shape must keep
   this constant tied to the same anchor date (1980-01-06) and re-derive it,
   not hardcode it independently.

## Coverage gap

The golden vectors (`legacy/tests/golden/pass01.tlm`, `pass02.tlm`,
`pass03.tlm`, `edge01.tlm`) only exercise `GPSSEC` values that decode to UTC
times in the range `2023-01-06 00:00:00` through `2023-01-06 03:01:16`
(per `legacy/tests/expected/*.out`, all `DOY=006`). This means:

- **No year rollover is exercised.** No golden vector produces a UTC
  timestamp crossing a year boundary (e.g. Dec 31 → Jan 1), so the
  walk-forward year loop (`geosat.f:479-486`) is only ever exercised for a
  single year (2023) and only for the earliest days of that year. A new
  vector is needed with a frame whose decoded `GPSSEC` (bytes at
  `FRMBUF(9..12)`, see `geosat.f:245`) corresponds to a UTC instant just
  before midnight Dec 31 of some year, to confirm `YR = YR + 1` and
  `UTCDOY` reset behave correctly across the boundary.
- **No leap-year February 29th is exercised.** No vector decodes to a date
  in February of a leap year (2024, 2028, ...), so the inline `DIM = 29`
  branch (`geosat.f:496-497`) and the corresponding `DINY = 366` branch
  (`geosat.f:481-482`) are untested by the golden suite (only unit-tested
  indirectly in `modern/tests/units.rs:147-152` via `to_utc`, which is not
  characterization coverage of the legacy binary itself). A new frame is
  needed with `GPSSEC` decoding to e.g. `2024-02-29`, to pin both the leap
  day-count and the day-of-year value (`UTCDOY = 60` for a leap year).
- **No century-leap-year edge (divisible by 100 but not 400, or by 400) is
  exercised.** Years like 2000 or 2100 are outside the mission timeframe
  reachable by any current golden vector; if ever relevant this needs its
  own vector, though it may be out of scope given mission epoch is ~2023+.
- **No negative or pre-epoch `GSEC` is exercised.** All frames decode to
  `GSEC` values that are safely post-epoch. The unterminated/incorrect
  behavior described above for very negative `TOTSEC` has zero pinned
  coverage. A new frame with a deliberately small/negative `GPSSEC` payload
  (bytes chosen so `FRMBUF(9..12)` decode to e.g. `GSEC = 0` or a small
  positive value near the epoch, and ideally one forcing `TOTSEC < 0`, i.e.
  `GSEC < 18`) would pin the near-epoch boundary condition described in
  `modern/tests/units.rs:140-145` (`to_utc(18)` → 1980-01-06) at the
  legacy-binary/golden-vector level, not just the Rust unit level.
- **No exercise of the manual REM-underflow branch** (`geosat.f:466-469`)
  at the legacy-binary level — it is implicitly always false for all
  current vectors since `TOTSEC >= 0` in every frame. A vector with
  `GSEC` between 0 and 17 (so `TOTSEC` goes negative before the day/time
  split) would exercise it directly.

## Incremental steps

1. **Add golden vectors for the identified coverage gaps** (year rollover,
   leap-year Feb 29, near-epoch/negative-`TOTSEC` boundary), generated by
   running the *existing, unmodified* `legacy/src/geosat.f` binary and
   capturing its output as the new expected fixture. This step touches only
   `legacy/tests/golden/*.tlm` and `legacy/tests/expected/*.out` (test
   fixtures), not `geosat.f`, `geosat.inc`, or `modern/`.
   - *Proof*: `make check` in `legacy/` passes with the new vectors added to
     its `pass01 pass02 pass03 edge01 ...` list, using the unmodified
     legacy binary as its own oracle.

2. **Extend `modern/tests/units.rs` with equivalence tests against the new
   fixtures**, calling `timebase::to_utc` directly with the `GPSSEC` values
   decoded from the new golden frames and asserting the fields match the
   corresponding lines in the new `legacy/tests/expected/*.out` files
   (year, month, day, hour, minute, second, day-of-year). This step touches
   only `modern/tests/units.rs` (adds tests; the routine itself,
   `modern/src/timebase.rs`, is not modified).
   - *Proof*: `cargo test --test units` passes, with each new test named
     after the scenario it pins (e.g. `year_rollover_matches_golden`,
     `leap_day_matches_golden`, `near_epoch_negative_totsec_matches_golden`).

3. **Add a characterization test in `modern/tests/characterization.rs`**
   that runs the new golden `.tlm` vectors through the full modern pipeline
   (if the pipeline already runs end-to-end against golden vectors — confirm
   by reading `characterization.rs` — otherwise this step is descoped to
   step 2's unit-level equivalence only, and that limitation is called out
   explicitly rather than silently skipped).
   - *Proof*: `cargo test --test characterization` passes and diffs the
     modern pipeline's `TIMBLK`-equivalent output byte-for-byte (or
     field-for-field) against `legacy/tests/expected/*.out` for the new
     vectors.

4. **Document the preserved defects explicitly as code comments** in
   `modern/src/timebase.rs` next to `LEAP_SECONDS` and the floor-division
   logic, cross-referencing this plan file and the specific `geosat.f` line
   numbers, so a future maintainer does not "fix" them without going through
   a deliberate, separately-reviewed change. (This plan itself already does
   this in prose; the code-comment step is optional polish, not required to
   close the equivalence gap, and is the only step in this plan that touches
   non-test modern source — it changes comments only, no logic.)

No step in this plan modifies `legacy/src/geosat.f`, `legacy/src/geosat.inc`,
or existing test files' pass/fail behaviour. Each step leaves the full
characterization suite (`legacy/tests`, `modern/tests`) green throughout.

## Proof obligation per step

| Step | Proof |
|---|---|
| 1 | `cd legacy && make check` passes with new vectors added; new `.out` fixtures are produced by running the unmodified legacy binary, not hand-authored. |
| 2 | `cargo test --test units -- <new_test_names>` pass, each asserting exact field equality against values transcribed from the corresponding new golden `.out` file. |
| 3 | `cargo test --test characterization` passes for the new vectors (or, if pipeline-level characterization is not currently wired for arbitrary golden files, this is documented as an explicit limitation rather than claimed as done). |
| 4 | Code review confirms comments cite this plan file and exact `geosat.f` line numbers for `LEAPS`, the day/rem floor-correction, and the `+5` epoch offset. |

## Explicitly out of scope

- Any change to the value of `LEAPS`/`LEAP_SECONDS`, or introduction of a
  maintained leap-second table. That is a behaviour change requiring its own
  plan, its own re-baselined golden vectors, and explicit sign-off that
  archived historical values are allowed to diverge from newly-computed ones.
- Any change to `/TIMBLK/` layout or addition of a two-digit-year field for
  `RTDISP`'s benefit — `RTDISP` is not present in this repository and its
  actual dependency on `/TIMBLK/` cannot be verified from this codebase.
- Any change to `GEOSAT`'s main driver (`geosat.f:75-79`), `ORBPRP`, or any
  other routine that consumes `GPSSEC`/`TIMBLK` fields.
- Any refactor of the truncating-division-plus-correction idiom into a
  single floored-division call, in either the Fortran or the Rust port,
  beyond what is required to *characterize* current behaviour (per
  Preserved Defect #2, such a refactor is safe only after the negative-input
  golden vector from step 1 exists and passes both before and after).
- Deduplicating the inline leap-year test that appears twice in `TIMCNV`
  (`geosat.f:481-482` and `495-497`) into a shared function — a legitimate
  future cleanup, but a structural change to `geosat.f` that this plan does
  not authorize.
- Performance or overflow hardening (e.g., guarding against 32-bit integer
  wraparound in `GSEC` for dates far in the future) — noted as a risk in
  "Current behaviour" but not remediated here.

## Open questions for a human

1. Is there a mission requirement (or archive-loader contract) that
   constrains how far into the future `GSEC` values must be correctly
   converted, given the frozen `LEAPS = 18` and the eventual need to insert
   a new leap second? This determines whether the "preserved defect" has a
   deadline.
2. Does `RTDISP` (referenced only in the `geosat.f:435-438` comment, and not
   present in this repository) actually consume `/TIMBLK/` fields today, and
   if so, in what format? This determines whether any future `/TIMBLK/`
   layout change is safe to consider at all, or permanently blocked.
3. Is a pipeline-level (not just unit-level) characterization harness for
   arbitrary golden `.tlm` vectors already wired in
   `modern/tests/characterization.rs`, or does step 3 above need its own
   preparatory infrastructure work first? This affects step 3's feasibility
   as scoped.
4. Who owns sign-off on new golden vectors being "correct" — i.e., is running
   the existing legacy binary against a synthetic frame and accepting its
   output as ground truth sufficient, or does an independent UTC calculation
   need to corroborate the new fixtures (particularly for the leap-year and
   negative-`TOTSEC` cases, where the legacy binary's behaviour is exactly
   the thing in question)?
