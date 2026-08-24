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

export PYTHONDONTWRITEBYTECODE=1
find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

STEP=0
FAILED=()

beat() {
  STEP=$((STEP + 1))
  printf '\n\033[1m[%d/7] %s\033[0m\n' "$STEP" "$1"
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

beat "Modern port is byte-for-byte identical to the legacy binary"
# Deliberately unpiped: `... | tail` reports tail's exit status and would mask
# a failing suite entirely.
check "characterization + unit suite" \
  bash -c 'cd modern && python3 -m unittest discover -s tests -t .'

beat "The suite can actually fail (mutation check)"
check "tools/mutation-check.sh" ./tools/mutation-check.sh

# Regression guard. The mutation check edits and reverts modules in place; a
# same-size revert inside one mtime tick once left a stale .pyc that made the
# suite pass against MUTATED code. Re-running parity here is what catches that
# class of failure, so this step must stay last.
beat "Parity still holds after the mutation check"
check "post-mutation parity" \
  bash -c 'cd modern && python3 -m unittest discover -s tests -t .'

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
