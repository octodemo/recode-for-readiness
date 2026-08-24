#!/usr/bin/env bash
#
# Rehearse -- run every offline beat of the demo end to end and fail loudly on
# any regression.
#
# This is the guarantee behind "works every time." Run it before every
# rehearsal and once more the morning of. If it exits 0, beats 1 through 3 and
# beat 5 will behave on stage exactly as they behave here.
set -uo pipefail

cd "$(dirname "$0")/.."

STEP=0
TOTAL=8
FAILED=()

beat() {
  STEP=$((STEP + 1))
  printf '\n\033[1m[%d/%d] %s\033[0m\n' "$STEP" "$TOTAL" "$1"
}

check() {
  local label="$1"
  shift
  if "$@" >/tmp/rehearse-step.log 2>&1; then
    printf '      \033[32mok\033[0m  %s\n' "$label"
  else
    printf '      \033[31mFAILED\033[0m  %s\n' "$label"
    sed 's/^/        /' /tmp/rehearse-step.log | tail -25
    FAILED+=("$label")
  fi
}

echo "Recode for Readiness -- full rehearsal"
echo "======================================"

beat "Legacy deck builds and reproduces its golden output"
check "make -C legacy check" make -C legacy check

beat "Knowledge graph builds with no network and no model"
check "tools/offline-proof.sh" ./tools/offline-proof.sh

beat "Graph answers the questions the demo asks it"
# The query commands resolve graphify-out relative to the working directory,
# so every one of them has to be issued from legacy/.
check "god-nodes"  bash -c 'cd legacy && graphify god-nodes --top 5 2>&1 | grep -qi geosat'
check "explain"    bash -c 'cd legacy && graphify explain "ORBPRP" 2>&1 | grep -q "geosat.f"'
check "path"       bash -c 'cd legacy && graphify path "geosat" "crcchk" 2>&1 | grep -qi crcchk'

beat "Rust port builds with the network off"
# The crate has no third-party dependencies on purpose. If someone adds one,
# the build starts needing a registry -- which a closed range will not have --
# and this step is where that gets caught, not in the room.
check "cargo build (offline)" \
  bash -c 'cd modern && CARGO_NET_OFFLINE=true cargo build --quiet'

beat "Modern port is byte-for-byte identical to the legacy binary"
# Deliberately unpiped: `... | tail` reports tail's exit status and would mask
# a failing suite entirely.
check "characterization + unit suite" bash -c 'cd modern && cargo test --quiet'

beat "The suite can actually fail (mutation check)"
check "tools/mutation-check.sh" ./tools/mutation-check.sh

# Regression guard. The mutation check edits and reverts sources in place. Under
# the previous Python port, a same-size revert inside one mtime tick left a
# stale .pyc that made the suite pass against MUTATED code, and it hid that for
# several rounds. Cargo keys on mtime too, so the same class of failure is
# possible here. Re-running parity AFTER the mutation check is what catches it,
# so this step must stay after step 6.
beat "Parity still holds after the mutation check"
check "post-mutation parity" bash -c 'cd modern && cargo test --quiet'

beat "Agentic workflows compile clean"
check "gh aw compile" bash -c 'gh aw compile 2>&1 | grep -q "0 warnings"'

echo
echo "======================================"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '\033[31mREHEARSAL FAILED\033[0m -- %d step(s):\n' "${#FAILED[@]}"
  printf '  - %s\n' "${FAILED[@]}"
  echo
  echo "Do not go on stage until these are green."
  exit 1
fi

echo -e "\033[32mREHEARSAL PASSED\033[0m -- every offline beat is reproducible."
echo
echo "Beat 4 runs live against GitHub Actions. Confirm separately with:"
echo "  gh aw status"
echo "and keep demo/artifacts/ as the fallback."
