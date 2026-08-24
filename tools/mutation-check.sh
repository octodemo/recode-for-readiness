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

# Mutations are same-length sed substitutions, so a mutated source can have the
# same size as the original and be reverted within the same filesystem-mtime
# tick. CPython's bytecode cache validates on (mtime, size) and will happily go
# on serving the MUTATED module afterwards, silently poisoning every later run.
# Never write bytecode here, and purge anything already cached.
export PYTHONDONTWRITEBYTECODE=1
purge_pycache() {
  find "$REPO" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
}
purge_pycache
trap purge_pycache EXIT

# Mutations are applied to the sources and reverted with `git checkout --`,
# so those paths -- and only those -- have to be clean. The graph output under
# legacy/graphify-out/ carries a rebuild timestamp and is deliberately excluded;
# otherwise simply having run `make graph` would block the check on stage.
DIRTY="$(git status --porcelain -- legacy/src modern/geosat_modern modern/tests)"
if [[ -n "$DIRTY" ]]; then
  echo "ERROR: mutation targets are dirty. Commit or stash before mutation testing." >&2
  echo "$DIRTY" >&2
  exit 2
fi

FAILED=0

# name | file | sed expression | what a human would call this change
run_mutation() {
  local name="$1" file="$2" expr="$3" rationale="$4"

  printf '  %-34s ' "$name"

  sed -i '' "$expr" "$file"

  if ! git diff --quiet -- "$file"; then
    : # mutation applied
  else
    printf 'SKIP (pattern did not match)\n'
    git checkout -- "$file"
    purge_pycache
    FAILED=1
    return
  fi

  if (cd modern && python3 -m unittest discover -s tests -t . >/dev/null 2>&1); then
    printf 'SURVIVED  <-- blind spot: %s\n' "$rationale"
    FAILED=1
  else
    printf 'caught\n'
  fi

  git checkout -- "$file"
  purge_pycache
}

echo "Mutation check -- each change below must be detected by the suite."
echo

run_mutation "crc polynomial off by one bit" \
  "modern/geosat_modern/crc.py" \
  's/POLYNOMIAL = 0x1021/POLYNOMIAL = 0x1020/' \
  "a corrupted CRC would pass frames that should be rejected"

run_mutation "silently fix the float32 defect" \
  "modern/geosat_modern/orbit.py" \
  's/    dt = f32(float(gps_seconds - ELEMENT_EPOCH_GPS))/    dt = float(gps_seconds - ELEMENT_EPOCH_GPS)/' \
  "improving precision changes every archived subsatellite point"

run_mutation "widen the overflowing F9.3 field" \
  "modern/geosat_modern/fortran.py" \
  's/        return "\*" \* width/        return text/' \
  "asterisk fill is what ARCLOD reads as no-value"

run_mutation "decouple channel 11 from byte 28" \
  "modern/geosat_modern/frame.py" \
  's/    raw\[10\] = (frame\[27\] \& 0x0F) \* 24/    raw[10] = (frame[29] \& 0x0F) * 24/' \
  "the wire format really is packed this way; see ECO 91-217"

run_mutation "refresh the stale leap-second count" \
  "modern/geosat_modern/timebase.py" \
  's/LEAP_SECONDS = 18/LEAP_SECONDS = 19/' \
  "a leap-second change shifts every decoded timestamp"

run_mutation "drop the eclipse thermistor fit" \
  "modern/geosat_modern/calibration.py" \
  's/C2 = \[0.0, 0.0, -1.2e-8,/C2 = [0.0, 0.0, 0.0,/' \
  "reverting to the linear fit reintroduces spurious eclipse alarms"

echo
if [[ $FAILED -eq 0 ]]; then
  echo "All mutations were caught. The characterization suite has teeth."
else
  echo "At least one mutation survived. The suite has a blind spot." >&2
fi

exit $FAILED
