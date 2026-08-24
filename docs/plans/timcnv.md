# Modernization Plan: TIMCNV

## Scope

`TIMCNV` (legacy: `legacy/src/geosat.f:440-509`) converts GPS seconds-of-epoch
(`GPSSEC`, from `/FRAME/`) into UTC calendar fields, written into `/TIMBLK/`
(`UTCYR, UTCMON, UTCDAY, UTCHR, UTCMIN, UTCSEC, UTCDOY`, declared in
`legacy/src/geosat.inc:45-47`). It is called exactly once per good frame, from
the main driver (`geosat.f:77`), between `LIMCHK` (`:76`) and `ORBPRP`
(`:78`). Per `legacy/graphify-out/graph.json`, `TIMCNV`'s only caller is
`GEOSAT` and it calls nothing itself — it is a leaf. `/TIMBLK/` is read only
by `REPORT` (`geosat.f:622-623`), which prints it via `FORMAT 902`
(`geosat.f:636-637`, `I4.4-I2.2-I2.2 I2.2:I2.2:I2.2  DOY=I3.3`). `ORBPRP`
takes `GPSSEC` directly, not `/TIMBLK/`, so `TIMCNV`'s output has no data
dependency into orbit propagation — it is purely a reporting-side
conversion, and the modern port (`modern/geosat_modern/timebase.py`) already
reflects that (`pipeline.py` calls `to_utc(frame.gps_seconds)` independently
of `propagate`).

## 1. Current behaviour

- **Leap-second back-out** (`:448`, `:462`): subtracts a hardcoded `LEAPS =
  18` from `GSEC` to get civil UTC seconds. This constant is manually
  maintained and, per the header comment (`:431-433`), was "last updated
  2016-12-31 (18)" — i.e. it has not been updated for any leap second
  announced since, and IERS has not added one since 2016, so it happens to
  still be correct as of today, but there is no mechanism that would catch
  drift if one is announced.
- **Negative remainder correction** (`:465-469`): integer division `TOTSEC /
  86400` in Fortran truncates toward zero, so for negative `TOTSEC` (i.e. any
  `GSEC` less than 18, which back-dates before the GPS epoch) `NDAYS` comes
  out one *too high* (toward zero) and `REM` comes out non-negative-but-wrong
  or negative. The code detects `REM .LT. 0` and corrects it by adding 86400
  to `REM` and decrementing `NDAYS`. This only fires for `GSEC < 18`; for
  `GSEC >= 18` it's a no-op. It has never been exercised by a golden vector
  (see Coverage gap).
- **Epoch walk-forward, not calendar math** (`:475-486`): rather than compute
  the year via a closed-form Julian-day algorithm, the routine starts at
  `YR = 1980`, adds 5 days (GPS epoch is Jan 6, so day-of-year offset), and
  then loops subtracting one year's length at a time until the remaining day
  count fits inside the current year. Leap year test at `:481-482` is a
  correct proleptic-Gregorian rule (`div4 and not div100, or div400`).
  `NDAYS` and `UTCDOY` (`:490`) end up 1-indexed against the *year the loop
  stopped in* — this only works because the loop always terminates on a
  year whose length exceeds the remaining day count, i.e. it is correct by
  construction, not an approximation.
- **Month walk-forward** (`:492-506`): same style, walking `MDAYS` months
  forward from January, re-deriving Feb length per iteration instead of
  reusing the leap flag computed above. This is a duplicate, not a discrepancy
  — `MOD(YR,4)`/`MOD(YR,100)`/`MOD(YR,400)` tests at `:496-497` are the exact
  same predicate as `:481-482`, just recomputed for the settled `YR`. No bug,
  but it is two copies of the same leap-year logic that must stay in sync by
  hand.
- **Two-digit year is not computed here.** The header comment (`:435-438`)
  warns that the 1998 Y2K windowing patch left a two-digit year *somewhere*
  "in `/TIMBLK/` for the benefit of the strip chart recorder driver," and
  that `UTCYR` is the full four-digit year and must not be "fixed." However,
  `/TIMBLK/` as declared in `geosat.inc:45-47` and as used by `TIMCNV`
  (`:489`) and `REPORT` (`:622-623`, format `I4.4` at `:636`) contains only
  the four-digit `UTCYR` — there is no two-digit year field in the visible
  deck. Either the two-digit field and `RTDISP` (the strip-chart driver it
  warns about) were never delivered into this repository, or the comment is
  stale relative to what's actually in this COMMON block. This is a
  documentation/behaviour mismatch worth flagging to a human (see Open
  Questions) rather than resolving unilaterally.
- **No bounds/overflow guard**: `GSEC` is a plain `INTEGER` (32-bit); for GPS
  seconds this rolls over years before it is a practical problem, but there
  is no explicit range check anywhere in `TIMCNV`.

## 2. Preserved defects

These are behaviours that look wrong in isolation but are load-bearing
because the downstream archive loader and/or other legacy consumers already
depend on the exact numbers `TIMCNV` currently produces:

- **Stale `LEAPS = 18` constant.** Correct only through the last IERS leap
  second (2016-12-31) and would silently under-count leap seconds after any
  future announcement. Must not be replaced with a live/maintained
  leap-second table as part of a port — that is a behaviour change with its
  own archived-value impact and needs its own reviewed change with new
  golden vectors, exactly as `modern/geosat_modern/timebase.py`'s own header
  comment (`:11-14`) already states. **Pin**: a test asserting
  `LEAPS`/`LEAP_SECONDS == 18` and that `to_utc` output for a fixed
  known-good `GPSSEC` matches the exact expected UTC fields, so an
  unreviewed table swap fails loudly.
- **Duplicated, not shared, leap-year predicate.** The year loop
  (`:481-482`) and month loop (`:496-497`) each recompute leap-year status
  independently. This is not incorrect for any in-range year, but a future
  "fix" that consolidates them into one shared flag *could* subtly change
  behaviour at a century boundary if done carelessly (e.g. if the flag were
  computed once for the *pre-loop* `YR` and never refreshed after the year
  loop advances `YR`). **Pin**: a golden/unit vector at a century-boundary
  year (e.g. GPS seconds landing on 2000-02-29 or 2100-02-28, whichever is
  in-range for the 32-bit `INTEGER GSEC` domain) asserting the exact
  `UTCMON`/`UTCDAY`/`UTCDOY` produced today, so consolidating the two loops
  can't accidentally use a stale flag without breaking a test.
- **Negative-remainder branch is unexercised but present.** It corrects
  truncating (toward-zero) division for `GSEC < LEAPS`. Nothing today
  requires this path (no golden vector reaches it), but the code exists and
  a "cleanup" that removes it because "it looks dead" would be removing
  intentional handling of an edge case the deck's author anticipated.
  **Pin**: add a new golden vector (see Coverage gap) that drives `GSEC`
  below 18 and pins the exact resulting UTC fields, including the
  correction.

## 3. Coverage gap

`legacy/tests/golden/{edge01,pass01,pass02,pass03}.tlm` and their expected
outputs in `legacy/tests/expected/` only ever show `GPSSEC` values that
correspond to 2023-01-06, always with `UTCYR=2023` and never near midnight
UTC on the GPS epoch itself or a leap-year February 29. Confirmed by
scanning all four `.out` files: every `UTC ...` line reports year 2023,
month 01, day 06, various times within the same day/hour windows (00:00:xx
and 01:30:xx), `DOY=006`. None of the following are exercised:

- **`GSEC < LEAPS` (negative-remainder branch, `:465-469`).** Needs a frame
  whose 4-byte `GPSSEC` field (`geosat.f:245`, bytes 9-12 of `FRMBUF`)
  decodes to a value less than 18, e.g. `GPSSEC = 10`. Expected UTC output
  would need to be hand-derived: `TOTSEC = 10 - 18 = -8`; Fortran truncating
  division gives `NDAYS = 0`, `REM = -8`; the correction branch fires,
  giving `REM = 86392`, `NDAYS = -1`; that yields `UTCHR=23, UTCMIN=59,
  UTCSEC=52` on the day *before* the GPS epoch reference (1980-01-05), i.e.
  `UTCYR=1980, UTCMON=1, UTCDAY=5, UTCDOY=5`. A new golden vector
  (`edge02.tlm`) with one otherwise-valid, CRC-correct frame carrying
  `GPSSEC=10` and this hand-computed expected line would close the gap.
- **Leap-day / century-boundary handling (`:481-482`, `:496-497`).** No
  vector lands on Feb 29 of any year, so the leap-year predicate (including
  its century exception) is never actually exercised — 2023 is not even
  close to a century boundary. Needs a frame with `GPSSEC` decoding to a
  moment on 2024-02-29 UTC (a normal leap year, `div4` true, `div100`
  false) at minimum, and ideally a second vector at a `div100`-but-not-
  `div400` non-leap year (e.g. 2100-02-28→03-01 transition, if in 32-bit
  `GSEC` range) to pin the century-exception branch specifically. Frame
  contents: same 32-byte structure as existing golden frames, sync word
  `1ACF`, valid SCID/APID/FRMCNT/CRC, with the GPSSEC bytes recomputed for
  the target instant.
- **Year rollover across Dec 31 → Jan 1.** No vector shows `UTCMON`
  transitioning from 12 to 1 with `UTCYR` incrementing, which is the one
  place the year-walk loop (`:479-486`) and month-walk loop (`:492-506`)
  must agree on which year they landed in before the month loop starts.
  Needs a frame at, e.g., 2023-12-31T23:59:58 GPS-equivalent through a
  following frame at 2024-01-01T00:00:0x.

## 4. Incremental steps

Each step below is independently reviewable and revertible, and must leave
`modern/tests/` and `legacy` characterization tests green before and after.
No step ports and changes behaviour in the same commit.

1. **Add the missing golden vectors described in §3** (new `.tlm`/`.out`
   pairs: `edge02` for the negative-remainder path, `edge03`/`edge04` for
   leap-day and century-boundary, `edge05` for year rollover), generated by
   running the *current* `legacy/src/geosat.f` binary and capturing its
   actual output — not hand-computing "correct" values. This step only adds
   fixtures; it changes no source.
   - **Proof**: `make -C legacy test` (or equivalent existing golden-vector
     runner) passes with the new vectors included, and a diff shows the new
     `.out` files were produced by the unmodified legacy binary.
2. **Add matching pinned unit tests to `modern/tests/test_units.py`** for
   `to_utc`, one per new scenario in step 1 (sub-epoch/negative remainder,
   leap day, century-exception, year rollover), asserting the exact field
   values captured from the legacy run. This step adds tests only — no
   change to `modern/geosat_modern/timebase.py`.
   - **Proof**: `python -m pytest modern/tests/test_units.py::TimebaseTest -v`
     — new tests pass against the *existing* `to_utc` implementation,
     demonstrating it already agrees with the legacy behaviour for these
     cases (or, if any fail, that becomes its own follow-up step to fix the
     port, not a modification bundled into this step).
3. **Add an explicit regression test pinning `LEAP_SECONDS == 18`** (and the
   legacy `LEAPS` constant, via a source-grep-based test if the
   characterization harness supports it, or a comment-linked assertion) so a
   future leap-second update cannot land silently.
   - **Proof**: a new test, e.g.
     `TimebaseTest.test_leap_seconds_constant_is_pinned`, fails if
     `LEAP_SECONDS` is changed without a corresponding deliberate PR
     touching this exact test.
4. **If step 2 uncovers any discrepancy between `to_utc` and legacy for the
   new vectors**, fix `modern/geosat_modern/timebase.py` in isolation to
   match legacy exactly, with no other changes bundled in.
   - **Proof**: the specific new unit test(s) from step 2 that were failing
     now pass; the full `modern/tests/` suite and full `legacy` golden-vector
     suite both remain green.
5. **Documentation-only step**: add a comment/note in
   `modern/geosat_modern/timebase.py` cross-referencing the new pinned
   defects (negative-remainder branch, duplicated leap-year predicate,
   stale leap-second constant) so a future contributor sees the rationale
   next to the code, mirroring what `geosat.f`'s own comments already say.
   - **Proof**: no test changes required; reviewer confirms the added
     comment accurately describes the pinned tests added in steps 2-3 by
     name.

No step in this plan proposes changing `LEAPS`/`LEAP_SECONDS`, the
negative-remainder correction, or the walk-forward algorithm's actual
output. Any such change is out of scope here (see below) and would need its
own plan.

## 5. Proof obligation per step

Already stated per-step above; summarized:

| Step | Proof |
|---|---|
| 1 | Existing legacy golden-vector test runner passes with new fixtures generated by the *unmodified* legacy binary |
| 2 | `pytest modern/tests/test_units.py::TimebaseTest -v` passes for new cases |
| 3 | New pinning test fails on constant change, passes otherwise |
| 4 (conditional) | The specific unit test(s) that started failing in step 2 now pass; full `modern/tests` and legacy suites stay green |
| 5 | Reviewer inspection only; no behavioural test implication |

## 6. Explicitly out of scope

- Replacing the hardcoded `LEAPS`/`LEAP_SECONDS = 18` with a maintained
  leap-second table or any live source. This changes every archived UTC
  timestamp computed after the next real leap second and is a
  mission-assurance decision, not a modernization mechanic.
- Consolidating the duplicated leap-year predicate (year loop vs. month
  loop) into one shared computation. Preserved as two independent copies per
  §2; any consolidation is a separate, deliberately-reviewed change.
- Replacing the walk-forward year/month/day algorithm with closed-form
  Julian-day arithmetic, even though it would be equivalent for all in-range
  inputs. Any algorithmic rewrite is out of scope until the characterization
  suite from step 1-2 exists and is proven green against it separately.
- Resolving the apparent inconsistency between the 1998 Y2K-patch comment
  (`:435-438`, which describes a two-digit year field in `/TIMBLK/`) and the
  actual `/TIMBLK/` layout in `geosat.inc`, which has no such field. This
  plan only documents the discrepancy (§1) and raises it as an open
  question below; it does not add, remove, or reinterpret any COMMON block
  member.
- `ORBPRP`, `ENGCNV`, `LIMCHK`, `REPORT`, decom/CRC logic, and any other
  routine in `geosat.f` not named `TIMCNV`. `REPORT`'s format string
  (`:636-637`) is treated as a fixed downstream contract and is not touched.
- Any change to `legacy/src/geosat.f`, `legacy/src/geosat.inc`, or any test
  file. This plan proposes only new fixtures and new tests under
  `legacy/tests/` and `modern/tests/`, plus documentation, per the task
  constraints.

## 7. Open questions for a human

1. **Two-digit year field.** The header comment at `geosat.f:435-438`
   references a two-digit year retained in `/TIMBLK/` "for the benefit of
   the strip-chart recorder driver" (`RTDISP`), but the actual `/TIMBLK/`
   declaration (`geosat.inc:45-47`) has no such field, and `RTDISP` does not
   appear anywhere in this deck. Is `RTDISP` a downstream consumer outside
   this repository that reads `UTCYR` and does its own truncation, is the
   comment stale from a prior deck revision, or was a field dropped at some
   point without updating the comment? This affects whether any future
   change to `UTCYR`'s type or range is safe.
2. **Leap-second update cadence.** `LEAPS = 18` has been correct since
   2016-12-31 by IERS' own leap-second moratorium, but IERS has signaled
   leap seconds may resume or be abolished by 2035 policy changes. Who owns
   the decision of when/how to update this constant, and does that decision
   require re-deriving every archived timestamp since the constant went
   stale, or only timestamps computed going forward? This is a policy call,
   not an engineering one.
3. **Century-boundary and negative-remainder golden vectors.** This plan
   proposes generating new golden vectors from the *existing* legacy binary
   (so they pin current behaviour, bugs included) rather than from an
   independently-derived "correct" UTC calculation. Confirm that is the
   intended validation approach for a flight system where the archive
   loader depends on today's exact (not textbook-correct) output.
4. **Scope of `RTDISP` investigation.** If `RTDISP` exists somewhere outside
   this repository/graph, should it be brought into the characterization
   scope before any future `TIMBLK`-touching change, given the explicit
   warning in the source comment not to change `UTCYR` "without checking
   RTDISP"?
