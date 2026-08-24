# Recode for Readiness — Demo Runbook

**Speaker:** Andrew Weiss, Field CTO, Regulated Industries, GitHub
**Slot:** GitHub portion of *Recode for Readiness* (Chapter 05 + live demo)
**Budget:** 18 minutes of content in a 20-minute slot
**Repo on screen:** `github.com/octodemo/recode-for-readiness`

---

**Podium reference:** `demo/CHEATSHEET.md`, or `make card`. Read this file end
to end before the room; use the card *in* the room.

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
to `demo/artifacts/`. A FAIL on `gfortran`, `cargo`, or `graphify` is not
survivable — fix it before you walk out.

```bash
make rehearse
```

Must print `REHEARSAL PASSED`. This is eight checks including the byte-parity
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

# Beat 0 — What this thing actually does

**~60 seconds. No terminal. Say this before you show anything.**

This exists because the room is mixed. Half the people in front of you have
never seen telemetry code and will spend the next fifteen minutes quietly lost
if you skip it. Do not skip it. No slides, no terminal — just say it.

> Yeah, before I show you any code, let me spend a minute on what this program
> even does, because not everybody in here works on satellites and I don't want
> anybody lost for the next fifteen minutes.
>
> So a satellite in orbit is basically a car where all the gauges got left back
> at the shop. It's got a battery, a transmitter, wheels spinning to point it —
> and it has to tell somebody on the ground how all of that is doing. So every
> few seconds it radios down a little packet of numbers. That's telemetry.
>
> And here's the part that matters. It does not send down "the battery is at 28
> volts." It sends down the number 23000. That's the whole message.
>
> So somebody in 1987 sat down with a calibration table and worked out that on
> *this* spacecraft, 23000 means 28.076 volts. Same for the current, the
> temperatures, the wheel speed, a dozen other things. Then what counts as too
> hot for each one. Then the orbit math, so you can say where the spacecraft
> actually was — its position over the Earth — at any given moment.
>
> That's this program. It turns a stream of numbers into a page an operator can
> actually read and act on.
>
> And this is the boring, unsexy stuff. There's no AI anywhere in it. But if
> it's wrong, the operator either misses something that's really going wrong up
> there, or goes chasing something that isn't. So it has to be exactly right,
> and it has to *stay* exactly right after we move it. That's the whole problem
> for the next fifteen minutes.

**Use the real numbers — 23000 and 28.076 are not made up.** They are the first
data line of `make beat1`, thirty seconds later:
`1 BUSV   23000    28.076 VDC       OK`. When it comes up on screen, point at it:
*"there's the 23000 I just told you about, and there's the 28 volts."* That
callback is free and it lands.

**If the room is heavily technical**, compress to the middle three sentences —
"it sends 23000, not 28 volts; the program is what knows the difference" — and
move on. Do not cut it entirely; the framing pays off in Beat 3.

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
> 642 lines of FORTRAN, fixed-form. And I'll translate one word before I start
> using it — this is a *deck*. That's the punch-card word for the source
> program. A deck was a literal stack of cards you carried down to the machine
> room, and ground-system shops never stopped calling it that. So when I say
> deck, I mean this file, not a slide deck.
>
> And that's the whole thing I just described — the translation, the red lines,
> the orbit math — all of it, in one file. It compiles, it runs, and if you look
> at the header there — the maintainer field literally says vacant. There's no
> design doc. The ECO numbers in the comments point at memos nobody can find
> anymore.

>
> And I want to be careful here, because the way we usually talk about this is
> "legacy code," which kind of implies it's bad. It's not bad. Code like this
> works, and it has worked every day for decades. The problem isn't quality.
> The problem is that the understanding left the building and the code stayed.

**Optional aside — only if you have the time or someone asks "why is it all one
file?"** Costs ~25 seconds. Verified against `legacy/src/geosat.f:11-15`.

> And that's also *why* it's one giant file. The header says it shipped as a
> single compilation unit because the old VMS build couldn't resolve the overlay
> segments otherwise. One deck, one compile. Splitting it into modules wasn't a
> thing you did. So this isn't sloppy — it's what the tooling of the day made
> you do, and you're still living with it.

Let `make check` land on screen. Four `PASS` lines.

> And there's the tell, right? It passes. So we're not being asked to fix
> something broken. We're being asked to move something that works, to a place
> it's never been, without changing what it does. That's a much harder problem,
> and honestly it's the one every single modernization program actually runs
> into.

**Fallback:** if the build hiccups — *"we've got the output from this morning's
run, let me pull that up"* — `cat demo/artifacts/beat1-legacy-check.txt`.

---

# Beat 2 — Make a map of it, without sending it anywhere

**~3 minutes.** The beat that matters most to this audience.

**Altitude check:** this room is mixed. Nobody needs to know how the tool works
internally. Two ideas only — *you can get a map of the system cheaply*, and
*making the map doesn't send your code anywhere*. Everything below serves those
two. If you catch yourself explaining parsers, you have lost the room.

> So step one is just understand what you've got. And this is usually where the
> conversation stops for folks in this room — because the obvious move is to
> hand the code to an AI and ask it, and for a lot of you, the code doesn't go
> anywhere. It can't leave the building.
>
> So let me not just assert that we solved that. Let me show you.
>
> The tool I'm about to run is called Graphify. Up front — it's not ours, it's
> not a GitHub product, and I'm not selling it to you. Open source, Apache 2.0,
> runs on your machine. If your shop already has something that does this, use
> that. The point isn't the tool.

```bash
make beat2
```

*Operator note (do not narrate):* the script drops every proxy variable, strips
model credentials from the environment, points egress at a dead port, and *then*
builds. It pins graphify's own `(no LLM needed)` line at the bottom, and states
in our own words that there is an optional model-backed layer we did not use.
Graphify's raw output also prints an upsell tip naming a third-party model
vendor; `tools/offline-proof.sh` filters that line out, since this is a joint
session with Microsoft and a competitor's brand on the projector helps nobody.
The substance it hints at is stated explicitly either way. Full mechanism is in
`tools/` if anyone asks after.

Now show it. This is the moment people remember.

```bash
make viz
```

*Operator note (do not narrate):* opens `legacy/graphify-out/graph.html` in the
browser. The rendering library is vendored into the repo and inlined into the
page, so it draws with the wifi physically off — which matters, because you just
finished saying nothing left the boundary. `make preflight` fails hard if that
file ever regains a CDN reference. Drag a node or two while you talk; it settles
and reads well from the back of a room.

> So what came back is a map of the program. Every routine in this thing, and
> every place one routine reaches for another. About a dozen pieces and the
> connections between them.
>
> And here's the thing I actually want you to take away. We built that map with
> every AI credential stripped off this box and outbound traffic pointed at a
> dead end. And I'll be straight with you — that's not the same as pulling the
> cable out of the wall. It's a software block, not an air gap. But it is
> demonstrable, it's on your screen, and the tool didn't want the network
> anyway. No AI spend, and nothing left the box.
>
> Because it never needed the AI to begin with. It *read* your source files and
> wrote down what it saw. It didn't ask anybody anything. And that distinction —
> reading versus asking — is the whole ball game for you all, because reading
> happens inside your boundary.
>
> And to be straight with you, the tool does offer an AI upgrade — you can point
> it at a model and get richer labelling out of it. We didn't. Didn't need it for
> this part, and nothing you just saw depends on it.
>
> And the limit, out loud, because it's a real one — this does not understand
> your code. It has no opinion about it. It's a map, not a guide. But a map is
> what you need first. GPS never made anybody a better driver. It just meant you
> stopped guessing about where you were.

Then let the map answer questions. **Stay in `legacy/` for all three commands.**

> And once you have the map, you can ask it things.

```bash
cd legacy && graphify god-nodes --top 5
```

> So: what's actually load-bearing in here? Top of the list is the main program
> — fine, that one's by design. But look at two and three. That's where
> everything in this system converges. Nobody designed that. It accreted, one
> change order at a time, over four decades.
>
> And that's the real architecture. Not the diagram on somebody's wall. And we
> got it in about a quarter of a second.
>
> And before anybody asks — this page isn't calling out to anything either. The
> whole thing, including the bit that draws it, is sitting in the repo. I could
> do this on a plane.

```bash
graphify explain "ORBPRP"
graphify path "geosat" "crcchk"
cd ..
```

> And the question your engineers actually ask: if I touch this, what else do I
> have to worry about? That's this.
>
> That routine there is `ORBPRP` — orbit propagate. Six-character names, by the
> way, because that was the limit in FORTRAN 77. It's the piece that works out
> where the spacecraft was over the Earth. Remember it, because it comes back
> twice.
>
> And every line of that answer comes with a file and a line number, so I can go
> open it and check it. Nothing here is a guess I have to take on faith.
>
> And here's why I'm spending real time on a map, in an AI talk.
>
> The way most people try this is they paste the whole thing into a model and
> say "modernize this." You'll get something back, and it'll look great, and you
> will have no idea which parts are real — because you gave the model no way to
> be checked.
>
> A map changes what you can ask for. Now it's: this *one* routine, here's what
> calls it, here's what it touches, go. That's a question with a right answer.
> And what comes back carries file and line numbers, so a human verifies it in a
> minute instead of re-reading the whole deck.
>
> You also stop doing this big-bang. One routine at a time, smallest blast
> radius first, always knowing what you just risked.
>
> And you'll see this land in five minutes — when I hand this to an agent, the
> first thing it does is go read this map. It's not guessing at your
> architecture. It's working from the facts you just watched me generate, inside
> your boundary, for free.
>
> Because the expensive part was never writing the new code. Everybody can write
> the new code. The expensive part is that nobody can tell you what the old code
> promised.

**Fallback:** graph queries must run from `legacy/` — the tool resolves
`graphify-out` relative to the working directory. If you get
`graph file not found`, you are in the wrong directory. `cd legacy` and repeat.
If graphify's CLI is broken: `make viz` and talk over the picture — it makes the
same point, and the page is self-contained so it does not care whether the CLI,
or the network, is having a good day.

---

# Beat 3 — Pin the behavior, then move it

**~5 minutes.**

> Okay. So we understand it. Now the actual dangerous part.

```bash
make beat3
```

Twenty-two tests. Read the parity result.

> There's a Rust port of this program in the repo. And the test you're looking
> at doesn't check that the Rust is *correct*. It compiles the 1987 FORTRAN,
> runs both of them on the same telemetry, and compares the output byte for
> byte.
>
> And that distinction is the whole thing. Because downstream of this there's
> an archive loader that parses this output by column position. So "equivalent"
> gets you an outage. It has to be identical.
>
> Quick note on why Rust, since somebody's going to ask. This deck declares
> every value as REAL(4) — 32-bit float. Rust has that as a native type, so the
> add, subtract, multiply and divide in the port match the 1987 numeric model
> to the bit, natively, instead of being emulated. And Rust won't fuse a
> multiply and an add behind your back, which is the exact thing we had to
> switch off in the FORTRAN compiler to make the two comparable at all.
>
> I'll caveat the one place that's not free — sines and cosines still go
> through the platform math library, so "byte identical" is a claim about the
> vectors we pinned on the hardware we pinned them on, not a law of physics.
> You'd re-pin on your target.
>
> Granted, all of that's a nice-to-have. The part that actually matters to you
> is that it's one binary — no interpreter, no garbage collector, and a
> zero-dependency crate graph. That's a much easier conversation with your ISSO
> than a language runtime on a closed network.

Now the part the room remembers:

```bash
make defect
```

> So while we were doing this, we found a bug. And I'd rather show you the
> symptom than describe it. Top block is the 1987 binary. Look at those three
> frames — the frame counter goes up, the UTC timestamp goes up, and the
> sub-satellite point is identical. Same latitude, same longitude, three frames
> in a row.
>
> Bottom block is the Rust port on the same telemetry. Same three frames, same
> frozen position, same everything.
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

**If asked "did you rewrite this by hand or did AI do it?"** — say it
straight: the port was written with Copilot, and every line of it is only
trustworthy because the characterization suite was written *first*, against
the compiled original. The tests are the deliverable. The port is the easy
part.

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

Derive the number — do **not** hardcode it. The repo already carries proven
reference runs, and your live dispatch opens a *new* one on top of them. Reading
the wrong PR in front of the room is the sort of thing people notice.
`max_by(.number)` always lands on yours.

That second command is worth typing on purpose — it shows the agent touched
exactly one path, and it is under `docs/plans/`.

> So this has been running since before I said hello. I pointed it at `ORBPRP`
> — orbit propagate, same one we mapped a few minutes ago. It read the graph we
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

# Beat 4b — The agent writes the port, and can't grade itself

**~3 minutes.** Right terminal. **This is the beat that answers "yeah but can it
actually *do* anything."**

Beat 4 showed an agent that plans. Fair pushback: planning is the safe half.
This is the other half — the agent writes production Rust — and the reason it's
safe has nothing to do with trusting the agent.

Runs on `main`. No staging branch, nothing deleted, nothing to reset — the
agent is told to throw away our port of one routine and derive it again from
the 1987 source. **Dispatch this at the same time as Beat 4's run**, before you
start talking — it takes about as long.

```bash
gh workflow run modernization-implement.lock.yml \
  --ref main -f routine=TIMCNV
```

> So the fair question after that last one is: fine, it wrote a *plan*. Plans
> are cheap. Can it actually do the work?
>
> So this one does. One routine — `TIMCNV`, time convert. Takes the raw seconds
> count off the spacecraft and turns it into an actual calendar date.
>
> We've already ported that one. So I told it to ignore our version completely,
> go back to the 1987 FORTRAN, and write it again from scratch. And then it has
> to clear the same bar the humans cleared: byte for byte, or it doesn't count.

Show the fencing first. This is the whole beat.

```bash
make beat4b
```

> Now — this agent writes Rust. Real code, into the real port. So look at what
> it's allowed to touch, because that's the entire safety story, and it isn't
> "we trust it."
>
> It can write `modern/src`. That's it. That's the whole list.
>
> It cannot land a change to the FORTRAN. That's the oracle — the thing that
> defines what correct even means. If it could edit that, "the port matches the
> original" would mean nothing at all.
>
> It cannot land a change to the golden vectors — those are the recorded outputs
> from the 1987 program that we check against. That's the evidence. Matching a
> file you were allowed to rewrite is not evidence of anything.
>
> And it cannot land a change to the tests. That's the judge. It does not get to
> grade its own homework.
>
> And I want to be precise about *how* that works, because this room cares about
> the difference. It's not that the prompt asks it nicely. It's that if the
> change it hands back touches any of those files, the workflow refuses to open
> the pull request at all.
>
> So there is exactly one way this agent gets a green pull request out of me. It
> has to actually reproduce what a person wrote in 1987, to the byte. It can't
> move the goalpost.

Then the result.

```bash
PR=$(gh pr list --json number --jq 'max_by(.number).number')
gh pr view "$PR" --json files --jq '.files[].path'
```

> And there it is. One file. `modern/src/timebase.rs`. Nothing else.

*Operator note (do not narrate):* because this now runs on `main`, the
**Files changed** tab is worth showing — it is the agent's re-derivation against
our human port, side by side. Expect the two to differ in style and agree in
behavior. If they came out nearly identical, that is a fine outcome too and the
body will say so; the line is "two independent passes at the same 1987 source
landed in the same place, which is what you want from a port."

Open the PR. Walk the body: what the routine does, preserved defects, numeric
decisions.

> And read the body, because this is where it gets interesting.
>
> Look at **numeric decisions**. The old code does its own little correction
> when a division comes out negative. Rust has a built-in that would give the
> same answer here — and it says, in writing, that it *knows* that, and chose
> not to use it anyway. Because "same answer today" isn't the bar. The bar is
> whether it matches what the 1987 deck actually specifies.
>
> That's the instinct you want. It's not chasing clever. It's chasing faithful.
>
> And look at **what was not done**. It says it left the shape of the function
> alone — the name, what goes in, what comes out — because other parts of the
> port already call it. That's the thing you want it worrying about. Don't break
> the neighbors while you're rebuilding the room.
>
> And then read **preserved defects**, which is the one I'd point at if you only
> look at one thing.
>
> The leap-second offset in this routine is a number somebody types in by hand.
> The header says it has to be updated every time the world adds a leap second,
> and it was last touched in 2016. That's a bug with a fuse on it.
>
> That one was already on the books as a known problem. Watch what it does with
> it. It copies the 2016 value forward exactly as-is, writes down that it did
> that on purpose, and says fixing it is its own change with its own updated
> test vectors — not something you quietly clean up while porting.
>
> Which is right, and it's the thing people get wrong. If it had helpfully fixed
> that on the way through, the output changes, parity breaks, and I've lost the
> only evidence I had that any of the rest of this is faithful. Fix it later, on
> purpose, with the tests updated deliberately.
>
> Is it an easy button? Still no. But it did the careful, expensive part
> — and it did it inside a fence where the worst case is that it wastes my time,
> not that it quietly breaks a spacecraft's ground segment.

**Fallback:** `cat demo/artifacts/implement-pr.md` and
`demo/artifacts/implement-run.log`. Real captured output.

**If you are cutting to 15 minutes, this beat and Beat 4 collapse into one** —
skip the plan PR entirely, dispatch only this one, and say "it plans too" over
the top of it. The fencing narration is what you keep.

---

# Beat 5 — Prove the tests can fail

**~2 minutes.** Left terminal.

> Last thing, and this is short. Everything I just showed you rests on that
> test suite. So a green suite is worth nothing until you've watched it go red.

```bash
make beat5
```

Six mutations, six `caught by the suite`.

> That introduces six real defects into the code — flips a bit in the CRC
> polynomial, quietly "fixes" the float32 bug, decouples the two telemetry
> channels that share a byte — and it requires the suite to catch every one.
> It does. That's the difference between tests that pass and tests that mean
> something.
>
> And look at the wording there — "caught by the suite." That's deliberate.
> In a typed language it's really easy to write a fake mutation the *compiler*
> rejects and then take credit for it. Every one of these compiles clean. The
> tests are what caught them.
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

## The pull requests from last time

Every dispatch opens a **new** pull request on a **new** branch. Nothing is
reused and nothing is overwritten. So if you rehearse twice and then run it for
real, there are six open pull requests with nearly identical titles and you are
picking one out of a list with a projector on.

Two commands handle it.

```bash
make prclean      # night before: close the stale ones
make pr-plan      # on stage: open the right one for beat 4
make pr-port      # on stage: open the right one for beat 4b
```

`prclean` keeps the newest pull request **for the routine each beat actually
demos** — the ORBPRP plan and the TIMCNV port — and closes the rest with a
comment saying why. It only ever touches `plan/*` and `port/*` branches, which
is what the workflows create, so a branch you made by hand is never in scope.

Why keep one at all: a real pull request in a browser is a much better live
fallback than the frozen markdown in `demo/artifacts/`. If your run is slow, or
the wifi in the room is what wifi in a conference room usually is, you open the
one from last night and the room cannot tell the difference. Close everything
with `make prclean PRCLEAN_ARGS=--all` if you would rather start clean.

`make pr-plan` and `make pr-port` resolve the right pull request by routine and
open it, so you never scan a list live. If the run has not finished, they say so
and print the `less demo/artifacts/...` command instead of failing quietly.

**Leave the kept ones open, and leave them as drafts.** If somebody asks whether
anything merged, the honest answer is the good answer: no, a human has not
approved these yet, and that is the point.

## Timing card

**Measured, not estimated.** Talk column is the actual spoken word count of the
block quotes at 155 wpm. Commands column is wall-clock, timed on a warm cache —
which is the real stage condition, since you will have run `make preflight` that
morning. Re-measure after any narration edit.

| Beat | Content | Talk | Commands | Target | Cumulative |
|---|---|---|---|---|---|
| 0 | What the thing does | 1:45 | — | 1:45 | 1:45 |
| 1 | The deck still runs | 2:36 | 0:05 | 2:41 | 4:26 |
| 2 | Map it, in-boundary | 5:06 | 0:15 | 5:21 | 9:47 |
| 3 | Characterize and port | 3:28 | 0:05 | 3:33 | 13:20 |
| 4 | Agent plans | 2:10 | 1:45 | 3:55 | 17:15 |
| 4b | Agent writes the port | 4:22 | 1:00 | 5:22 | 22:37 |
| 5 | Mutation check and close | 1:36 | 0:10 | 1:46 | 24:23 |

The "commands" time on Beats 4 and 4b is you walking a pull request in the
browser, which is the one place you will naturally run long.

### Read this before you build the run of show

**24:23 is over your slot. Run Beat 4 or Beat 4b — not both.** They make the
same argument twice, and the second telling is always the one that gets rushed.

| Run of show | Lands at | Pick it when |
|---|---|---|
| **4b, drop 4** | 20:28 | **Default.** The room's real objection is "can AI actually build anything." 4b answers it and still shows `safe-outputs`. |
| 4, drop 4b | 19:01 | The room is governance-first — auditors, ISSMs, ATO people. A plan a human approves is the friendlier first contact. |
| Both | 24:23 | Only if you genuinely have 25+ minutes and no Q&A. |

Either way you still dispatch **both** runs at T-10, because it costs nothing
and gives you a live spare if one run is slow or fails.

Real rooms add pauses, a laugh, and someone interrupting with a question, so
whichever you pick, **plan on that number plus two**. Two optional adds not
counted above: the "why is it one file?" aside in Beat 1 (0:25) and the show of
hands (0:30).

### Cut list, in order

| Cut | Saves | Cost |
|---|---|---|
| Beat 2 → drop `graphify explain` + `path`, keep `god-nodes` | 0:50 | Lose the blast-radius question. The AI bridge still works. |
| Beat 4 → skip `cat`-ing the workflow, say `safe-outputs` over the PR | 0:50 | Lose "you can read the whole agent" |
| Beat 0 → the three-sentence version | 1:15 | Non-technical half is thinner in Beat 3 |
| Beat 1 → skip the show of hands, skip the aside | 0:55 | Colder open |
| Beat 2 → drop the "paste it into a model" paragraph | 0:30 | Weakens the *why AI needs this* argument. Last resort. |

Applied on top of the 4b-only run of show (20:28), the first two cuts get you
to **18:48**, and the first three to **17:33**. If you are running 4b and your
slot includes Q&A, **take the first two cuts before you walk up** — 4b is the
longest beat in the deck and it is the one you least want to rush.

### Never cut

- **Beat 5.** Shortest beat, and it is what makes the other four credible.
  Without it you are just asserting the tests work.
- **`make defect` in Beat 3.** Best thirty seconds in the demo. If you are long
  at Beat 3, cut narration around it, not it.
- **The air-gap concession in Beat 2** — "it's a software block, not an air
  gap." Saying it out loud is what buys you the rest of the claim in this room.
- **The "not a GitHub product" line on Graphify.** Cheap, and it inoculates the
  obvious cynical read.

## Routine names — what they actually stand for

FORTRAN 77 capped identifiers at six characters, so everything is vowel-dropped
shorthand. Nobody in a mixed room can decode these on sight, and you will say at
least two of them out loud. **Expand a name the first time you say it**, then use
the short form freely.

| Name | Says | Does | Where |
|---|---|---|---|
| `RDFRM` | "read frame" | Reads one hex telemetry record off stdin | `geosat.f` |
| `TLMDEC` | "telemetry decom" | Unpacks the frame into channels. *Decom* = decommutate, the standard term for splitting a multiplexed stream back into signals | `geosat.f` |
| `CRCCHK` | "CRC check" | CCITT CRC-16 over the frame, catches corrupted downlink | `crc.rs` |
| `HEXVAL` | "hex value" | One hex character to an integer | `fortran.rs` |
| `ENGCNV` | "engineering convert" | Raw counts to engineering units — 23000 to 28.076 volts. The Beat 0 example | `calibration.rs` |
| `LIMCHK` | "limit check" | Screens each channel against its red lines, raises the alarm flags | `calibration.rs` |
| `ORBPRP` | "orbit propagate" | Works out where the spacecraft was over the Earth. **Carries the known defect** | `orbit.rs` |
| `TIMCNV` | "time convert" | GPS seconds to UTC calendar time, including the hand-maintained leap-second constant | `timebase.rs` |
| `REPORT` | "report" | Formats the pass summary. Fixed column positions the archive loader parses | `report.rs` |

Two worth knowing cold, because they carry the demo:

- **`ORBPRP` — orbit propagate.** Beat 2 asks the graph about it, Beat 4 plans
  it, Beat 3's `make defect` is its defect. Its own header says it ignores J2,
  drag and all maneuver history, and tells you not to use it for pointing or
  conjunction. It is a quick-look estimate that outlived its caveat.
- **`TIMCNV` — time convert.** Beat 4b re-derives it from the FORTRAN. The leap-second offset is
  a hand-edited constant, last updated 2016-12-31, and the header says it "must
  be hand edited when IERS announces a new leap second." That is a maintenance
  landmine sitting in a `DATA` statement, and it is real — this is how it was
  actually done.

**If someone asks why the names are like that:** six characters was the FORTRAN
77 identifier limit. That's the whole reason. It's a good throwaway — it lands
the age of the code better than any adjective.

---

## Known failure modes

| Symptom | Cause | What you do |
|---|---|---|
| `graph file not found` | graphify resolves `graphify-out` from cwd | `cd legacy` first |
| Parity suite fails right after `make mutants` | stale cargo fingerprint from a same-mtime revert | `make reset`; the harness `touch`es every source on each mutation revert, so this should not recur |
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
