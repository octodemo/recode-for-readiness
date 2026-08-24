#!/usr/bin/env bash
# Open the pull request the agent just made, without hunting for it on stage.
#
# The whole point: you never click "Pull requests" and scan a list in front of
# the room. You ask for the newest plan PR or the newest port PR by name and it
# opens. Works no matter how many old ones are lying around.
#
#   tools/openpr.sh plan     newest Modernization Plan PR      (Beat 4)
#   tools/openpr.sh port     newest Modernization Implement PR (Beat 4b)
#   tools/openpr.sh port --print   print the URL instead of opening it
#
# If nothing is open -- no network, run failed, run still going -- it says so
# and points at the frozen copy in demo/artifacts/ rather than failing silently.
set -euo pipefail

kind="${1:-}"
mode="${2:-open}"

# The beats demo specific routines, and the frozen fallbacks are from those
# same routines. Matching on prefix alone would happily hand you a plan PR for
# a different routine from some earlier experiment, which is exactly the sort
# of thing you do not want to discover with a projector on. Override via env if
# you ever demo a different routine.
case "$kind" in
  plan) beat="Beat 4"
        routine="$(echo "${DEMO_PLAN_ROUTINE:-ORBPRP}" | tr 'A-Z' 'a-z')"
        fallback="demo/artifacts/modernization-plan-pr.md" ;;
  port) beat="Beat 4b"
        routine="$(echo "${DEMO_PORT_ROUTINE:-TIMCNV}" | tr 'A-Z' 'a-z')"
        fallback="demo/artifacts/implement-pr.md" ;;
  *) echo "usage: tools/openpr.sh <plan|port> [--print]" >&2; exit 2 ;;
esac

fallback_msg() {
  echo ""
  echo "  No open ${kind} pull request for ${routine} found${1:+ -- $1}."
  echo "  ${beat} runs from the frozen copy instead:"
  echo ""
  echo "      less ${fallback}"
  echo ""
}

command -v gh >/dev/null 2>&1 || { fallback_msg "gh not installed"; exit 0; }
gh auth status >/dev/null 2>&1 || { fallback_msg "gh not authenticated"; exit 0; }

url=$(
  gh pr list --state open --limit 100 \
     --json url,headRefName,createdAt \
     --jq "[.[] | select(.headRefName | startswith(\"${kind}/\"))
                | select(.headRefName | contains(\"${routine}\"))]
           | sort_by(.createdAt) | reverse | .[0].url // empty" 2>/dev/null || true
)

if [ -z "$url" ]; then
  fallback_msg "the run may still be going -- check 'gh run list'"
  exit 0
fi

if [ "$mode" = "--print" ]; then
  echo "$url"
else
  echo "${beat}: ${url}"
  gh pr view "$url" --web >/dev/null 2>&1 \
    || echo "  (could not open a browser -- the URL above is the one you want)"
fi
