#!/usr/bin/env bash
#
# Mutation check -- prove the characterization suite can actually fail.
#
# A test suite that has never failed is not evidence of anything. Before this
# demo claims that characterization tests protect the modernization, it has to
# demonstrate that they detect a behaviour change.
#
# Each mutation below is a plausible, well-intentioned "cleanup" that a
# refactor might make. Every one of them must be caught. If any mutation
# survives, the suite has a blind spot and this script exits non-zero.
#
# Usage:  tools/mutation-check.sh
set -uo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"

# Mutations are sed substitutions applied in place and reverted with
# `git checkout --`. Cargo decides whether to rebuild from source mtimes, so a
# revert landing inside the same timestamp as the mutation could in principle
# leave a stale binary in target/ and silently poison every later run. Bump the
# mtime explicitly after every write so that can never happen.
#
# This is the Rust-shaped version of a bug this repo was already bitten by
# once: under the previous Python port, CPython's bytecode cache validates on
# (mtime, size), same-length mutations reverted within one mtime tick kept
# serving the MUTATED module, and the parity suite lied about it for several
# rounds. Rehearsal step 6 re-runs parity AFTER this script for exactly that
# reason. Do not remove it.
touch_sources() {
  find "$REPO/modern/src" "$REPO/modern/tests" -name '*.rs' -exec touch {} + 2>/dev/null || true
}

# Mutations are applied to the sources and reverted with `git checkout --`,
# so those paths -- and only those -- have to be clean. The graph output under
# legacy/graphify-out/ carries a rebuild timestamp and is deliberately excluded;
# otherwise simply having run `make graph` would block the check on stage.
DIRTY="$(git status --porcelain -- legacy/src modern/src modern/tests)"
if [[ -n "$DIRTY" ]]; then
  echo "ERROR: mutation targets are dirty. Commit or stash before mutation testing." >&2
  echo "$DIRTY" >&2
  exit 2
fi

restore() {
  git checkout -- legacy/src modern/src modern/tests 2>/dev/null || true
  touch_sources
}
trap restore EXIT

FAILED=0

# name | file | sed expression | what a human would call this change
run_mutation() {
  local name="$1" file="$2" expr="$3" rationale="$4"

  printf '  %-34s ' "$name"

  sed -i '' "$expr" "$file"
  touch_sources

  if git diff --quiet -- "$file"; then
    printf 'SKIP (pattern did not match)\n'
    git checkout -- "$file"
    touch_sources
    FAILED=1
    return
  fi

  # Distinguish the two gates on purpose.
  #
  # In a typed language it is easy to write a mutation the COMPILER rejects and
  # then claim the test suite caught it. That is not the claim this demo makes.
  # Every mutation below is meant to compile cleanly and be caught by the
  # characterization suite; a compile failure is reported honestly as such, and
  # is treated as a defect in the mutation, not a success.
  if ! (cd modern && cargo build --quiet >/dev/null 2>&1); then
    printf 'REJECTED BY COMPILER  <-- mutation is not a valid program\n'
    FAILED=1
    git checkout -- "$file"
    touch_sources
    return
  fi

  # Deliberately unpiped and fully redirected: piping this into `tail` would
  # report tail's exit status, which reads green no matter what cargo did.
  if (cd modern && cargo test --quiet >/dev/null 2>&1); then
    printf 'SURVIVED  <-- blind spot: %s\n' "$rationale"
    FAILED=1
  else
    printf 'caught by the suite\n'
  fi

  git checkout -- "$file"
  touch_sources
}

echo "Mutation check -- each change below must be detected by the suite."
echo

run_mutation "crc polynomial off by one bit" \
  "modern/src/crc.rs" \
  's/pub const POLYNOMIAL: u16 = 0x1021;/pub const POLYNOMIAL: u16 = 0x1020;/' \
  "a corrupted CRC would pass frames that should be rejected"

run_mutation "silently fix the float32 defect" \
  "modern/src/orbit.rs" \
  's|let dt = (gps_seconds - ELEMENT_EPOCH_GPS) as f32;|let dt = (gps_seconds - ELEMENT_EPOCH_GPS) as f64;|; s|let u = TWO_PI \* (dt / period);|let u = TWO_PI as f64 * (dt / period as f64);|; s|let arg_lat = fmod(u, TWO_PI);|let arg_lat = (u % (TWO_PI as f64)) as f32;|; s|let lon_ascending = ELEMENT_RAAN_DEG - rate \* dt;|let lon_ascending = ELEMENT_RAAN_DEG - (rate as f64 * dt) as f32;|' \
  "improving precision changes every archived subsatellite point"

run_mutation "widen the overflowing F9.3 field" \
  "modern/src/fortran.rs" \
  's/        return "\*".repeat(width);/        return text;/' \
  "asterisk fill is what ARCLOD reads as no-value"

run_mutation "decouple channel 11 from byte 28" \
  "modern/src/frame.rs" \
  's/raw\[10\] = ((frame\[27\] \& 0x0F) as i32) \* 24;/raw[10] = ((frame[29] \& 0x0F) as i32) * 24;/' \
  "the wire format really is packed this way; see ECO 91-217"

run_mutation "refresh the stale leap-second count" \
  "modern/src/timebase.rs" \
  's/pub const LEAP_SECONDS: i64 = 18;/pub const LEAP_SECONDS: i64 = 19;/' \
  "a leap-second change shifts every decoded timestamp"

run_mutation "drop the eclipse thermistor fit" \
  "modern/src/calibration.rs" \
  's/\[0.0, 0.0, -1.2e-8,/[0.0, 0.0, 0.0,/' \
  "reverting to the linear fit reintroduces spurious eclipse alarms"

echo
if [[ $FAILED -eq 0 ]]; then
  echo "All mutations were caught. The characterization suite has teeth."
else
  echo "At least one mutation survived. The suite has a blind spot." >&2
fi

exit $FAILED
