# Recode for Readiness — Demo Runbook

**Speaker:** Andrew Weiss, Field CTO, Regulated Industries, GitHub
**Slot:** GitHub portion of *Recode for Readiness* (Chapter 05 + live demo)
**Budget:** 18 minutes of content in a 20-minute slot
**Repo on screen:** `github.com/octodemo/recode-for-readiness`

---

## How to read this

Everything in a `> quote block` is what you say. Everything in a fenced block is
what you type. Every beat has a **fallback** line — if the beat misbehaves, you
say the fallback and keep moving. You never debug in front of the room.

Two terminal windows, both already in `~/Development/recode-for-readiness`:

- **Left (big font, the one they watch)** — every command below.
- **Right (small, yours)** — the dispatched Actions run. They never see it until
  Beat 4.

---

## T-30 minutes — preflight

```bash
make preflight
```

Wants `0 failed`. Warnings on the `gh` lines are survivable; Beat 4 falls back
to `demo/artifacts/`. A FAIL on `gfortran`, `python3`, or `graphify` is not
survivable — fix it before you walk out.

```bash
make rehearse
```

Must print `REHEARSAL PASSED`. This is seven checks including the byte-parity
suite and the mutation check. If it does not pass, you are demoing from
`demo/artifacts/` and you should decide that now, calmly, not on stage.

```bash
make reset
```

Puts the repo back to stage-start state.

---

## T-10 minutes — start the agent before you start talking

This is the single most important operational decision in the demo. Measured on
2026-08-24 in `octodemo/recode-for-readiness`, the agent job took **5m00s** and
the full run including safe-output detection took **8m26s** before the pull
request appeared. Beat 4 lands about 16 minutes into an 18-minute demo, so a
dispatch at T-10 gives you roughly seven minutes of margin.

Nobody watches a spinner. Start it before your first word and come back to it.

If someone else is speaking ahead of you, dispatch it while they are still on.

In the **right-hand** terminal:

```bash
gh workflow run modernization-plan.lock.yml -f routine=ORBPRP
```

Then walk to the front of the room.

---

# Beat 1 — The deck still runs, and nobody knows why

**~2 minutes.** Left terminal.

```bash
make beat1
```

You get the file header, the line count, and four passing golden vectors.

> Yeah, so before I show you anything, quick show of hands — how many folks
> here are running something in production today that was written before you
> got there, and there's nobody left who wrote it? Okay. Yeah. That's most of
> the room.
>
> So this is that. And let me say up front what this is — this is a stand-in I
> built for today. It's synthetic, so that it can live on a public repo and you
> can all go clone it. But it's modeled line for line on the ground software
> you actually run, and every pathology in it is one we've hit for real.
>
> 642 lines of FORTRAN, fixed-form, decodes telemetry coming down off a
> satellite. It compiles, it runs, and if you look at the header there — the
> maintainer field literally says vacant. There's no design doc. The ECO
> numbers in the comments point at memos nobody can find anymore.
>
> And I want to be careful here, because the way we usually talk about this is
> "legacy code," which kind of implies it's bad. It's not bad. Code like this
> works, and it has worked every day for decades. The problem isn't quality.
> The problem is that the understanding left the building and the code stayed.

Let `make check` land on screen. Four `PASS` lines.

> And there's the tell, right? It passes. So we're not being asked to fix
> something broken. We're being asked to move something that works, to a place
> it's never been, without changing what it does. That's a much harder problem,
> and honestly it's the one every single modernization program actually runs
> into.

**Fallback:** if the build hiccups — *"we've got the output from this morning's
run, let me pull that up"* — `cat demo/artifacts/beat1-legacy-check.txt`.

---

# Beat 2 — Comprehension, and it never leaves the building

**~4 minutes.** This is the beat that matters most to this audience.

> So step one is understand it. And this is where, for you all, the
> conversation usually stops — because the natural move is to throw the code at
> a model, and for a lot of what's in this room, the code doesn't go anywhere.
>
> So let me not assert that. Let me just show you.

```bash
make beat2
```

The script blackholes every proxy variable, strips every model API key, and
*then* rebuilds the graph. Note the `Tip: set GEMINI_API_KEY...` line graphify
prints — you are going to name it before anyone else does.

> So the call-graph extraction here is pure tree-sitter. It's a parser. It
> reads the source the same way your compiler does and writes down what calls
> what. Twelve nodes, nineteen edges, nine resolved call edges.
>
> And I want to be straight with you about the tool, because you can see it
> right there on screen — graphify has an *optional* semantic layer that will
> call out to Gemini if you give it a key. We didn't turn that on. And rather
> than just tell you that, we stripped every model credential on the box and
> pointed the proxy at a dead port before building. It built anyway, at zero
> token cost, because the structural map never needed a model to begin with.
>
> Now, is blackholing a proxy the same thing as an air-gap? No. If you want the
> hard version, the tool runs fine with the network physically down — there's a
> flag in the repo that does exactly that. The architectural point is the one
> that matters: parsing is not inference. That part runs inside your boundary.
>
> And I'll say the limit out loud too — this does not understand your code. It
> has no opinion about it. It's a map, not a guide.
>
> But a map is what you actually need first. It's kind of like — you can drive
> across the country with a paper map from twenty years ago, and you'll
> probably get there, and it's going to be miserable. GPS didn't make you a
> better driver. It just meant you stopped guessing.

Then the graph answers questions. Stay in `legacy/` for all three.

> So now I can ask it things.

```bash
cd legacy && graphify god-nodes --top 5
```

> Top of that list is the main program, which — fine, that one's by design.
> But look at two and three. `RDFRM` and `TLMDEC` are the real hubs in this
> thing. Nobody sat down and designed that. It accreted, one change order at a
> time, over four decades. And that's the honest architecture of this system,
> and we got it in about a quarter of a second.

```bash
graphify explain "ORBPRP"
graphify path "geosat" "crcchk"
cd ..
```

> `explain` gives me the neighborhood with a file and a line number on every
> edge — that's not a model's best guess, that's read straight out of the
> source, and I can go open line 78 and check it.
>
> And `path` is the blast-radius question. If I touch the CRC check, what sits
> upstream of me. Two hops, main into `TLMDEC` into `CRCCHK`.
>
> And the reason I'm spending time on this — the expensive part of
> modernization was never writing the new code. It's that nobody can tell you
> what the old code promised. This part costs you nothing and it happens inside
> your boundary.

**Fallback:** graph queries must run from `legacy/` — the tool resolves
`graphify-out` relative to the working directory. If you get
`graph file not found`, you are in the wrong directory. `cd legacy` and repeat.
If graphify itself is broken: `open legacy/graphify-out/graph.html`.

---

# Beat 3 — Pin the behavior, then move it

**~5 minutes.**

> Okay. So we understand it. Now the actual dangerous part.

```bash
make beat3
```

Twenty-one tests. Read the parity result.

> There is a Python port of this program in the repo. And the test you're
> looking at doesn't check that the Python is *correct*. It compiles the 1987
> FORTRAN, runs both of them on the same telemetry, and compares the output
> byte for byte.
>
> And that distinction is the whole thing. Because downstream of this there's
> an archive loader that parses this output by column position. So "equivalent"
> gets you an outage. It has to be identical.

Now the part the room remembers:

```bash
make defect
```

> So while we were doing this, we found a bug. And I'd rather show you the
> symptom than describe it. Look at those three frames — the frame counter goes
> up, the UTC timestamp goes up, and the sub-satellite point is identical. Same
> latitude, same longitude, three frames in a row.
>
> The elapsed-time value in the orbit propagator is about seven hundred and
> thirty million seconds and it's carried in single precision. It doesn't fit.
> So four seconds of motion rounds away to nothing, and the spacecraft appears
> to be parked. That's been wrong since 1987.
>
> And here's the uncomfortable part, and this is the part I'd push on if I were
> sitting where you're sitting — we did not fix it. It's in the port, wrong, on
> purpose, with a test pinning it that way.
>
> Because thirty-eight years of archived data were produced by that bug. Fixing
> it means every historical value stops matching. That's not an engineering
> call. That's a mission call, it goes to a human, and it goes on a completely
> separate change than the one that moves the language.
>
> There are five of these preserved in the repo. Stale leap seconds. Two
> telemetry channels sharing a byte because of a wiring change in '91. The
> error message that prints the wrong frame number. All pinned, all documented,
> none of them fixed.
>
> If an AI tool cleans those up for you silently because they look like bugs,
> it just corrupted your archive and it was very confident about it.

**Fallback:** if parity fails on stage, do not debug. Say *"that's a real
failure and I'll take it offline — here's this morning's run"* and
`cat demo/artifacts/beat3-parity.txt`. A characterization suite that fails
loudly is on-message; pretending it passed is not.

---

# Beat 4 — Hand the loop to an agent, in CI, in the open

**~5 minutes.** Switch to the right terminal.

> So everything so far has been me typing. Let's give the loop to an agent.
> And I want to be specific about what that means, because "agent" is doing an
> enormous amount of work in a lot of vendor decks right now.

```bash
cat .github/workflows/modernization-plan.md
```

Scroll to the frontmatter and stop on `safe-outputs`.

> This is GitHub Agentic Workflows. It's markdown. The prose is the prompt —
> that's the whole body of the file. And the frontmatter is the part I care
> about.
>
> Look at `safe-outputs`. The only thing this agent is permitted to emit is a
> pull request. Not a push, not a merge, not a comment. And `allowed-files`
> fences it to `docs/plans`. It cannot write to the FORTRAN. It cannot write to
> the port. It cannot write to the tests. That's not a prompt asking it nicely.
> That's the harness refusing.
>
> And it's a draft PR by design, because approving a plan is not approving a
> change.

Now the run you started before you began talking:

```bash
gh pr list
PR=$(gh pr list --json number --jq 'max_by(.number).number')
gh pr view "$PR" --json files --jq '.files[].path'
```

Derive the number — do **not** hardcode `1`. PR #1 is the frozen reference run;
your live dispatch opens a new one, and reading the wrong PR in front of the
room is the sort of thing people notice.

That second command is worth typing on purpose — it shows the agent touched
exactly one path, and it is under `docs/plans/`.

> So this has been running since before I said hello. It read the graph we
> built in Beat 2, it read the deck, it read the tests, and it opened this.

Open the PR in the browser. Walk the plan: current behavior with line citations,
preserved defects, coverage gaps, ordered steps, proof obligation per step.

> And notice what it did *not* do. It didn't refactor anything. It wrote down
> what it found, it flagged what it wasn't authorized to decide, and it handed
> that to a person. Every step in there names the test that proves it.
>
> This runs in Actions. Which means it's the same audit trail, the same branch
> protections, the same reviewers, the same everything you already have. It's
> not a new system to govern. That's kind of the point — the review process you
> already spent years getting accredited is the review process for the agent.
>
> Is this an easy button? No. It got things wrong when we were building it, and
> a human reads every one of these. But the thing it's good at is exactly the
> thing that's expensive — reading forty-year-old code carefully and writing
> down what it promises.

**Fallback:** if the run is still going or Actions is unavailable —
*"we've got one from earlier"* — open `demo/artifacts/modernization-plan-pr.md`
and `demo/artifacts/modernization-plan-run.log`. Both are real output from run
[32678748126](https://github.com/octodemo/recode-for-readiness/actions/runs/32678748126),
not a mockup. Do not refresh the Actions page in front of the room.

**Reference PR:** https://github.com/octodemo/recode-for-readiness/pull/1

---

# Beat 5 — Prove the tests can fail

**~2 minutes.** Left terminal.

> Last thing, and this is short. Everything I just showed you rests on that
> test suite. So a green suite is worth nothing until you've watched it go red.

```bash
make beat5
```

Six mutations, six caught.

> That introduces six real defects into the code — flips a bit in the CRC
> polynomial, quietly "fixes" the float32 bug, decouples the two telemetry
> channels that share a byte — and it requires the suite to catch every one. It does. That's the difference between tests that pass and
> tests that mean something.
>
> So, three things to take with you.
>
> Comprehension is a parser problem before it's a model problem, and the parser
> part runs inside your boundary today, for free, with no data leaving.
>
> Characterize before you move. Byte-for-byte against the real binary, and when
> you find a bug that's forty years old, pin it and escalate it — don't let
> anything fix it quietly.
>
> And put the agent inside the harness you already have. `safe-outputs`, draft
> PRs, a human on the approval. Not a new governance regime. The one you've got.
>
> Everything I just ran is in `octodemo/recode-for-readiness`. Clone it, run
> `make rehearse`, and it'll do all of that on your machine. Go point it at
> something of yours.

---

## Timing card

| Beat | Content | Target | Cumulative |
|---|---|---|---|
| 1 | The deck still runs | 2:00 | 2:00 |
| 2 | In-boundary comprehension | 4:00 | 6:00 |
| 3 | Characterize and port | 5:00 | 11:00 |
| 4 | Agentic loop in CI | 5:00 | 16:00 |
| 5 | Mutation check and close | 2:00 | 18:00 |

**If you are running long at Beat 3**, cut `make defect` and just say it. Saves
90 seconds. It is the best moment in the demo though, so cut something else
first if you can.

**If you are running long at Beat 4**, skip `cat`-ing the workflow file and go
straight to the PR. Say the `safe-outputs` line over the PR view instead.

**Never cut Beat 5.** It is the shortest beat and it is the one that makes the
rest of it credible.

---

## Known failure modes

| Symptom | Cause | What you do |
|---|---|---|
| `graph file not found` | graphify resolves `graphify-out` from cwd | `cd legacy` first |
| Parity suite fails right after `make mutants` | stale `.pyc` from a same-size, same-tick revert | `make reset`; the harness now sets `PYTHONDONTWRITEBYTECODE` |
| `make mutants` refuses to run | mutation targets are dirty | commit or `git checkout -- legacy/src modern` |
| Agentic run still going at Beat 4 | dispatched too late; it needs ~8m30s | `demo/artifacts/` |
| Agentic run fails on the engine | org Copilot billing / missing token | `demo/artifacts/` — do not troubleshoot live |

## Questions you will get

**"How much of this is GitHub-specific?"**
> Yeah, good question. The graph part isn't — that's tree-sitter, it's open
> source, it runs anywhere. The agentic part is, in the sense that it's riding
> on Actions and pull requests. But that's kind of deliberate, right? The value
> isn't the agent. It's that the agent's output lands in a review process you
> already accredited.

**"What about COBOL? Ada? We don't have FORTRAN."**
> Yeah, so — I'll be straight with you, this particular tool ships a FORTRAN
> grammar and it does not ship COBOL or Ada today. Tree-sitter grammars exist
> for both, so it's a packaging problem more than a research problem. And I'd
> say the method is the portable part. Characterize, pin the defects, prove
> byte parity, fence the agent. None of that is language-specific.

**"Can the agent do the refactor, not just the plan?"**
> It can. We didn't let it here, and I'd push back a little on wanting that
> early. The reason the plan is the deliverable is that the plan is the thing a
> human can actually review in ten minutes. A four-thousand-line diff isn't
> reviewable, so nobody reviews it, and then you've automated the part that was
> already cheap.

**"How do you know the port is right?"**
> We don't know it's *right*. We know it's *identical*, which is a different
> and better claim for this problem. It reproduces the 1987 binary byte for
> byte, including the bugs. Correctness is a separate change, on purpose, with
> a human on it.

**"Did the model see our source?"**
> Not in Beat 2, and that's demonstrable — that's what the blackholed egress
> was showing. In Beat 4 it did, because that's an agent running in your CI
> against your repo under your existing data terms. Two different trust
> boundaries, and you get to choose how far right you go.
