# Cheat sheet — one page, for the podium

Full script: `demo/DEMO-RUNBOOK.md`. This is the glance-down version.

The arc, if you lose the thread: **it still runs → we can understand it → we
can prove parity → an agent can help → the proof is real.**

```
cd ~/Development/recode-for-readiness
make                    # this menu, any time you forget
```

---

## Night before / morning of

```bash
make preflight          # want: 0 failed
make rehearse           # want: REHEARSAL PASSED (8/8)
make reset              # working tree
make prclean            # open PRs -- closes stale runs, keeps one of each
```

`rehearse` not passing means you demo from `demo/artifacts/`. Decide that now,
not on stage.

## T-10 min — RIGHT terminal, before you speak

```bash
gh workflow run modernization-plan.lock.yml -f routine=ORBPRP
gh workflow run modernization-implement.lock.yml --ref main -f routine=TIMCNV
```

Both run on `main`. Nothing to stage, nothing to reset. Plan ~8m30s, implement
~13m. Beat 4 is ~16 min in. **Do not skip this.**

---

## On stage — LEFT terminal, big font

| # | Beat | Command | Min |
|---|---|---|---|
| 0 | What it does | *no terminal — just talk* | 1 |
| 1 | Deck still runs | `make beat1` | 2 |
| 2 | Map it, in-boundary | `make beat2` → `make viz` → queries below | 3 |
| 3 | Characterize + port to Rust | `make beat3` → `make defect` | 4:30 |
| 4 | Agent plans | *right terminal*, see below | 5 |
| 4b | Agent writes the port | *right terminal*, PR from run 2 | 3 |
| 5 | Tests can fail | `make beat5` | 2 |

**Over 20 min? Cut 4b, keep 4.** If they want proof it can *build*, not just
plan, invert it: cut 4, keep 4b.

**Beat 2 picture** — `make viz`. Self-contained, renders with wifi off.

**Beat 2 queries** — the only time you leave the repo root:

```bash
cd legacy
graphify god-nodes --top 5
graphify explain "ORBPRP"
graphify path "geosat" "crcchk"
cd ..
```

**Opening the agent's PR** — never scan the list on stage:

```bash
make pr-plan            # beat 4  -- newest ORBPRP plan PR
make pr-port            # beat 4b -- newest TIMCNV port PR
```

Says so and points at `demo/artifacts/` if the run isn't done.

**Beat 4** — right terminal:

```bash
cat .github/workflows/modernization-plan.md      # stop on safe-outputs
gh pr list
PR=$(gh pr list --json number --jq 'max_by(.number).number')
gh pr view "$PR" --json files --jq '.files[].path'
```

Derive the PR number with `max_by(.number)`. Never hardcode it — the reference
runs are older and lower-numbered than your live one.

Proven reference runs are already in the repo, draft, fenced to `docs/plans/`.
Worth saying out loud: it ran on more than one routine and landed in the same
place every time.

---

## Fallbacks — say the line, cat the file, keep moving

| Beat | File |
|---|---|
| 1 | `demo/artifacts/beat1-legacy-check.txt` |
| 2 | `demo/artifacts/beat2-offline-proof.txt`, `beat2-graph-queries.txt` |
| 3 | `demo/artifacts/beat3-parity.txt`, `beat3-defect.txt` |
| 4 | `demo/artifacts/modernization-plan-pr.md`, `...-run.log` |
| 5 | `demo/artifacts/beat5-mutants.txt` |

All real captured output, not mockups. Never debug live.

---

## Five things to internalize, not read

0. **Beat 0** — 60 seconds, no terminal. "It sends 23000, not 28 volts. This
   program is what knows the difference." Mixed room; do not skip it.
1. **Beat 1** — say it's synthetic up front. Don't let them ask. Gloss the word
   **deck** the first time you use it ("punch-card word for the source program,
   not a slide deck") — you're standing in front of a slide deck saying it.
2. **Beat 2** — stay high. Two ideas only: *you get a map cheaply*, and
   *making it sends your code nowhere*. Say **reading, not asking** out loud;
   keep "parsing is not inference" in your pocket for the technical follow-up.
   Say the optional model layer exists and you skipped it — the vendor tip is
   filtered from the output, so nothing names a competitor on screen. Proxy
   blackhole is not an air-gap; say so. Do not explain parsers.
   `make viz` is the picture. It renders offline; say that out loud.
3. **Beat 3** — `make defect` is the best 30 seconds in the demo. It sits still
   for four frames, then **teleports 251 miles**. Say what *should* happen first
   (~19 miles per frame) or the room won't see it. And you did **not** fix it.
4. **Beat 5** — never cut it. It's what makes the other four credible.

## Routine names (expand on first use)

Six characters was the FORTRAN 77 limit — that's why they look like this.

| `ORBPRP` | **orbit propagate** — where it was over the Earth. Carries the defect. |
|---|---|
| `TIMCNV` | **time convert** — GPS seconds to UTC. Hand-edited leap second. Beat 4b re-derives it. |
| `ENGCNV` | **engineering convert** — 23000 → 28.076 volts |
| `TLMDEC` | **telemetry decom** — unpack the frame into channels |
| `LIMCHK` | **limit check** — screen against red lines |
| `CRCCHK` | **CRC check** · `RDFRM` read frame · `HEXVAL` hex value |

Only `ORBPRP` and `TIMCNV` need to be cold. Full table in the runbook.

## If you're long

- Cut `make defect` (−90s). Cut something else first if you can.
- Cut `cat`-ing the workflow file in Beat 4; say the `safe-outputs` line over
  the PR view instead.
- **Never cut Beat 5.**

## If something's off

| Symptom | Fix |
|---|---|
| `graph file not found` | you're not in `legacy/` |
| parity fails after `make mutants` | `make reset` |
| `cargo` not found | `source ~/.cargo/env`, then `make preflight` |
| `make mutants` refuses | `git checkout -- legacy/src modern` |
| agent run still going | `demo/artifacts/` — you dispatched late |

## Do not

- Run `tools/offline-proof.sh --airplane` if you are screen-sharing over Wi-Fi.
  It powers the interface down.
- Refresh the Actions page in front of the room.
