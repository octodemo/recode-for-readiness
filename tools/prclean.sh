#!/usr/bin/env bash
# Tidy up the agent-generated pull requests between demo runs.
#
# Every dispatch of an agentic workflow opens a NEW pull request on a NEW
# branch. Rehearse twice and run the demo once and you are standing on stage
# looking at six pull requests with nearly identical titles, picking one out of
# a list in front of the room. This closes the old ones.
#
# By default it KEEPS the newest of each kind, because a real pull request in a
# browser is a much better live fallback than the frozen markdown in
# demo/artifacts/ if a run is slow. Pass --all to close everything.
#
#   tools/prclean.sh            keep the newest plan PR and the newest port PR
#   tools/prclean.sh --keep 2   keep the newest two of each
#   tools/prclean.sh --all      close every agent PR
#   tools/prclean.sh --dry-run  show what would happen, change nothing
#
# Only touches branches named plan/* or port/*, which is what gh-aw's
# safe-outputs create. A hand-made branch is never in scope.
set -euo pipefail

KEEP=1
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     KEEP=0 ;;
    --keep)    KEEP="${2:?--keep needs a number}"; shift ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "prclean: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

case "$KEEP" in
  ''|*[!0-9]*) echo "prclean: --keep needs a non-negative integer" >&2; exit 2 ;;
esac

command -v gh >/dev/null 2>&1 || { echo "prclean: gh not found -- nothing to do"; exit 0; }
gh auth status >/dev/null 2>&1 || { echo "prclean: gh not authenticated -- nothing to do"; exit 0; }

closed=0
kept=0

plan_routine="$(echo "${DEMO_PLAN_ROUTINE:-ORBPRP}" | tr 'A-Z' 'a-z')"
port_routine="$(echo "${DEMO_PORT_ROUTINE:-TIMCNV}" | tr 'A-Z' 'a-z')"

for prefix in plan port; do
  # Keep the newest PR for the routine the demo actually uses, not just the
  # newest PR of this kind -- Beat 4 demos ORBPRP, so a newer TIMCNV plan from
  # some experiment is clutter, not the spare.
  case "$prefix" in
    plan) routine="$plan_routine" ;;
    port) routine="$port_routine" ;;
  esac
  # createdAt descending, so the newest survivors are first.
  # Deliberately a while-read over process substitution rather than mapfile:
  # macOS ships bash 3.2 and mapfile is bash 4+. Process substitution keeps the
  # loop in the current shell, so the counters below actually survive it.
  i=0
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    num="${row%%$'\t'*}"
    rest="${row#*$'\t'}"
    branch="${rest%%$'\t'*}"
    title="${rest#*$'\t'}"

    # Anything for a different routine is never the spare.
    case "$branch" in
      *"$routine"*) is_spare=1 ;;
      *)            is_spare=0 ;;
    esac

    if [ "$is_spare" -eq 1 ] && [ "$i" -lt "$KEEP" ]; then
      echo "  keep  #${num}  ${title}"
      kept=$((kept + 1))
      i=$((i + 1))
      continue
    elif [ "$DRY" -eq 1 ]; then
      echo "  close #${num}  ${title}  (dry run)"
      closed=$((closed + 1))
    else
      # -d deletes the remote branch too, so the branch list stays as short as
      # the pull request list.
      if gh pr close "$num" -d \
           -c "Closing a superseded demo run. The agentic workflows open a new pull request on every dispatch; this one is from an earlier rehearsal." \
           >/dev/null 2>&1; then
        echo "  close #${num}  ${title}"
        closed=$((closed + 1))
      else
        echo "  SKIP  #${num}  could not close (check permissions)" >&2
      fi
    fi
  done < <(
    gh pr list --state open --limit 100 \
       --json number,headRefName,title,createdAt \
       --jq "[.[] | select(.headRefName | startswith(\"${prefix}/\"))]
             | sort_by(.createdAt) | reverse
             | .[] | \"\(.number)\t\(.headRefName)\t\(.title)\"" 2>/dev/null || true
  )
done

if [ "$closed" -eq 0 ] && [ "$kept" -eq 0 ]; then
  echo "prclean -- no agent pull requests open"
else
  suffix=""
  [ "$DRY" -eq 1 ] && suffix=" (dry run -- nothing changed)"
  echo "prclean -- ${kept} kept as live fallback, ${closed} closed${suffix}"
fi
