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
make reset
```

`rehearse` not passing means you demo from `demo/artifacts/`. Decide that now,
not on stage.

## T-10 min — RIGHT terminal, before you speak

```bash
gh workflow run modernization-plan.lock.yml -f routine=ORBPRP
```

Agent takes ~8m30s. Beat 4 is ~16 min in. Do not skip this.

---

## On stage — LEFT terminal, big font

| # | Beat | Command | Min |
|---|---|---|---|
| 1 | Deck still runs | `make beat1` | 2 |
| 2 | In-boundary comprehension | `make beat2` → then queries below | 4 |
| 3 | Characterize + port to Rust | `make beat3` → `make defect` | 5 |
| 4 | Agent in CI | *right terminal*, see below | 5 |
| 5 | Tests can fail | `make beat5` | 2 |

**Beat 2 queries** — the only time you leave the repo root:

```bash
cd legacy
graphify god-nodes --top 5
graphify explain "ORBPRP"
graphify path "geosat" "crcchk"
cd ..
```

**Beat 4** — right terminal:

```bash
cat .github/workflows/modernization-plan.md      # stop on safe-outputs
gh pr list
PR=$(gh pr list --json number --jq 'max_by(.number).number')
gh pr view "$PR" --json files --jq '.files[].path'
```

Derive the PR number. Do not hardcode `1` — that's the frozen reference run.

Two proven runs already in the repo (`#1` ORBPRP, `#2` TIMCNV), both draft,
both fenced to `docs/plans/`. Worth saying out loud: it ran twice, on two
routines, and landed in the same place both times.

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

## Four things to internalize, not read

1. **Beat 1** — say it's synthetic up front. Don't let them ask.
2. **Beat 2** — name graphify's optional Gemini layer *before* they see the
   `Tip: set GEMINI_API_KEY` line on screen. Proxy blackhole is not an air-gap;
   say so. The claim is *parsing is not inference*.
3. **Beat 3** — `make defect` is the best 30 seconds in the demo. Clock moves,
   spacecraft doesn't. And you did **not** fix it.
4. **Beat 5** — never cut it. It's what makes the other four credible.

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
