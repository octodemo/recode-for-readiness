#!/usr/bin/env bash
#
# Preflight -- run this before walking on stage.
#
# Checks every dependency the demo actually touches and reports each one
# individually, so a failure names the thing to fix rather than just failing.
# Exit 0 means every beat of the demo can run.
set -uo pipefail

cd "$(dirname "$0")/.."

PASS=0
FAIL=0
WARN=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; WARN=$((WARN + 1)); }

have() { command -v "$1" >/dev/null 2>&1; }

echo
echo "Recode for Readiness -- preflight"
echo "================================="
echo
echo "Required for the offline beats (1-3). These must pass."
echo

if have gfortran; then
  ok "gfortran $(gfortran -dumpversion)"
else
  bad "gfortran not found -- 'brew install gcc'"
fi

if have cargo; then
  ok "cargo $(cargo --version | cut -d' ' -f2)"
else
  bad "cargo not found -- https://rustup.rs"
fi

if have rustc; then
  ok "rustc $(rustc --version | cut -d' ' -f2)"
else
  bad "rustc not found -- https://rustup.rs"
fi

if have python3; then
  ok "python3 $(python3 -V 2>&1 | cut -d' ' -f2) (graph tooling only)"
else
  warn "python3 not found -- graphify and 'make graph' need it"
fi

if have graphify; then
  ok "graphify $(graphify --version 2>&1 | tr -d '\n')"
else
  bad "graphify not found -- 'uv tool install graphifyy'"
fi

if have git; then
  ok "git $(git --version | cut -d' ' -f3)"
else
  bad "git not found"
fi

echo
echo "Required for the live agentic beat (4). A failure here drops to the"
echo "frozen artifacts in demo/artifacts/, which is a supported path."
echo

if have gh; then
  ok "gh $(gh --version | head -1 | cut -d' ' -f3)"
else
  warn "gh not found -- beat 4 runs from frozen artifacts"
fi

if have gh && gh auth status >/dev/null 2>&1; then
  ok "gh authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"
else
  warn "gh not authenticated -- beat 4 runs from frozen artifacts"
fi

if have gh && gh aw version >/dev/null 2>&1; then
  ok "gh aw $(gh aw version 2>&1 | grep -oE 'v[0-9.]+' | head -1)"
else
  warn "gh aw extension missing -- 'gh extension install github/gh-aw'"
fi

if curl -s --max-time 6 https://api.github.com >/dev/null 2>&1; then
  ok "github.com reachable"
else
  warn "github.com unreachable -- beat 4 runs from frozen artifacts"
fi

echo
echo "Repository state."
echo

if [[ -f legacy/src/geosat.f ]]; then
  ok "legacy deck present ($(wc -l < legacy/src/geosat.f | tr -d ' ') lines)"
else
  bad "legacy/src/geosat.f missing"
fi

for f in legacy/tests/golden/*.tlm; do
  [[ -e "$f" ]] || { bad "no golden telemetry vectors"; break; }
done
[[ -e legacy/tests/golden/pass01.tlm ]] && \
  ok "$(ls legacy/tests/golden/*.tlm | wc -l | tr -d ' ') golden vectors present"

if [[ -f legacy/graphify-out/graph.json ]]; then
  ok "knowledge graph present"
else
  warn "no graph yet -- 'make graph' will build it in under a second"
fi

# The Rust port must have no third-party dependencies, or `cargo build` needs
# a network and a registry the demo room may not have. Cargo.lock naming only
# this crate is the cheap proof.
if [[ -f modern/Cargo.lock ]]; then
  DEPS="$(grep -c '^name = ' modern/Cargo.lock || echo 0)"
  if [[ "$DEPS" -eq 1 ]]; then
    ok "Rust port has zero dependencies (builds offline)"
  else
    warn "Cargo.lock names $DEPS packages -- the build now needs a registry"
  fi
else
  warn "modern/Cargo.lock missing -- run 'cargo build' in modern/ and commit it"
fi

# A quoting mistake in one of these is invisible until the beat runs, and it
# would surface mid-demo. `bash -n` costs nothing.
BADSH=""
for script in tools/*.sh; do
  bash -n "$script" 2>/dev/null || BADSH="$BADSH $script"
done
if [[ -z "$BADSH" ]]; then
  ok "$(ls tools/*.sh | wc -l | tr -d ' ') harness scripts parse cleanly"
else
  bad "syntax error in:$BADSH"
fi

if compgen -G ".github/workflows/*.lock.yml" >/dev/null; then
  ok "$(ls .github/workflows/*.lock.yml | wc -l | tr -d ' ') agentic workflows compiled"
else
  bad "workflows not compiled -- 'gh aw compile'"
fi

# Named explicitly rather than globbed: the runbook cites these four files by
# path, so a glob that matches some other stray file would report a fallback
# that is not actually there.
missing_art=""
for a in modernization-plan-pr.md modernization-plan-run.log \
         implement-pr.md implement-run.log; do
  [ -s "demo/artifacts/$a" ] || missing_art="$missing_art $a"
done
if [ -z "$missing_art" ]; then
  ok "frozen fallback artifacts present (beats 4 and 4b)"
else
  warn "missing frozen artifacts:$missing_art"
fi

if git ls-files --error-unmatch docs/plans/.gitkeep >/dev/null 2>&1; then
  ok "docs/plans/ is tracked (agent can write its plan)"
else
  bad "docs/plans/ not tracked -- the plan agent cannot mkdir and WILL fail"
fi

if [[ -z "$(git status --porcelain -- legacy/src modern/src modern/tests)" ]]; then
  ok "mutation targets clean ('make mutants' can run)"
else
  warn "mutation targets dirty -- 'make mutants' will refuse to run"
fi

echo
echo "---------------------------------"
printf '  %d passed, %d warnings, %d failed\n' "$PASS" "$WARN" "$FAIL"
echo

if [[ $FAIL -gt 0 ]]; then
  echo "NOT READY. Fix the failures above before going on stage."
  exit 1
fi

if [[ $WARN -gt 0 ]]; then
  echo "READY -- beats 1-3 will run. Beat 4 may fall back to frozen artifacts."
  exit 0
fi

echo "READY. Every beat can run live."
