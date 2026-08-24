# Recode for Readiness -- demo driver
#
# Every target here is something run on stage or immediately before it.
# Nothing in this file requires the network except `beat4`.

SHELL := /usr/bin/env bash

# NOTE: macOS ships GNU Make 3.81, which silently ignores `.SHELLFLAGS`
# (added in 3.82). Setting it here would look like protection and provide
# none. Any recipe that pipes therefore says `set -o pipefail;` inline --
# otherwise `cargo test | tail` reports tail's exit status and a completely
# failing suite reads as success. This repo has already been bitten by
# exactly that in tools/rehearse.sh.

GRAPH   := legacy/graphify-out/graph.json
GRAPH_HTML := legacy/graphify-out/graph.html
VECTOR  := pass01

.PHONY: help card preflight rehearse legacy graph offline-proof parity \
        mutants workflows beat1 beat2 beat3 beat4 beat5 beat4b defect \
        reset prclean pr-plan pr-port viz clean

help:
	@echo ""
	@echo "  Recode for Readiness -- GEOSAT telemetry processor"
	@echo ""
	@echo "  Before the room:"
	@echo "    make card           print the one-page podium cheat sheet"
	@echo "    make preflight      check every dependency, name what is missing"
	@echo "    make rehearse       run every offline beat end to end"
	@echo "    make reset          return the repo to its stage-start state"
	@echo "    make prclean        close stale agent PRs from earlier runs"
	@echo ""
	@echo "  On stage:"
	@echo "    make beat1          the deck still runs, and nobody knows why"
	@echo "    make beat2          comprehension, in-boundary, no model"
	@echo "    make beat3          characterize, port to Rust, prove byte parity"
	@echo "    make defect         the clock moves, the spacecraft does not"
	@echo "    make beat4          hand the loop to an agent, in CI"
	@echo "    make beat4b         the agent writes the port, and cannot cheat"
	@echo "    make beat5          prove the tests can fail"
	@echo "    make pr-plan        open the agent's plan PR   (beat 4)"
	@echo "    make pr-port        open the agent's port PR    (beat 4b)"
	@echo ""
	@echo "  Parts:"
	@echo "    make legacy         build and run the 1987 FORTRAN deck"
	@echo "    make graph          build the knowledge graph"
	@echo "    make viz            open the interactive graph (works offline)"
	@echo "    make offline-proof  rebuild the graph with egress blackholed"
	@echo "    make parity         characterization + unit suite (cargo test)"
	@echo "    make mutants        mutation check (needs a clean tree)"
	@echo "    make workflows      compile the agentic workflows"
	@echo ""

card:
	@cat demo/CHEATSHEET.md

preflight:
	@./tools/preflight.sh

rehearse:
	@./tools/rehearse.sh

legacy:
	@$(MAKE) -C legacy check

# Every rebuild regenerates graph.html with a CDN <script> tag in it, so the
# localize step has to run every time, not once.
$(GRAPH):
	@graphify update legacy 2>&1 | grep -v -E 'GEMINI_API_KEY|GOOGLE_API_KEY|[Gg]emini' || true
	@./tools/localize-graph.sh >/dev/null

graph: $(GRAPH)
	@python3 -c "import json;g=json.load(open('$(GRAPH)'));print('%d nodes, %d edges'%(len(g['nodes']),len(g['links'])))" 2>/dev/null \
	  || echo "graph built: $(GRAPH)"

# The picture. Self-contained, so this works with the wifi off.
viz: $(GRAPH)
	@./tools/localize-graph.sh >/dev/null
	@echo "  opening $(GRAPH_HTML) -- fully offline, nothing is fetched"
	@open $(GRAPH_HTML) 2>/dev/null || echo "  open it manually: $(GRAPH_HTML)"

offline-proof:
	@./tools/offline-proof.sh

parity:
	@cd modern && cargo test

mutants:
	@./tools/mutation-check.sh

workflows:
	@gh aw compile

# ---------------------------------------------------------------- beats

# ~2 min. The deck compiles and runs. That is the whole point: it works, it is
# in the critical path, and its author is gone.
beat1:
	@clear
	@echo "== legacy/src/geosat.f -- GEOSAT telemetry processor, 1987 =="
	@sed -n '1,28p' legacy/src/geosat.f
	@echo
	@echo "$$(wc -l < legacy/src/geosat.f | tr -d ' ') lines. One compilation unit."
	@echo
	@$(MAKE) -C legacy check

# ~4 min. Comprehension without sending the source anywhere.
# Deliberately the proof only. The graph queries are typed live from legacy/ so
# that whichever one is being narrated is the last thing on screen.
beat2:
	@clear
	@./tools/offline-proof.sh

# ~5 min. Pin the behaviour, port it to Rust, prove it did not move.
beat3:
	@clear
	@echo "== 1987 FORTRAN -> Rust, byte-for-byte against the original binary =="
	@echo
	@set -o pipefail; cd modern && cargo test 2>&1 | grep -Ev '^\s*$$' | tail -22

# The single-precision time-overflow defect, preserved on purpose.
#
# Three consecutive frames four seconds apart. UTC advances. The subsatellite
# point does not, because DT is carried in REAL(4) and the low bits are gone.
# The port reproduces it exactly -- and deliberately does not fix it.
defect:
	@clear
	@echo "== frames four seconds apart, per the 1987 binary =="
	@$(MAKE) -C legacy all >/dev/null 2>&1
	@set -o pipefail; ./legacy/build/geosat < legacy/tests/golden/$(VECTOR).tlm \
	  | grep -n "SCID=\|UTC \|SSP LAT" | sed -n '1,9p'
	@echo
	@echo "== and the Rust port, on the same input =="
	@cd modern && cargo build --quiet 2>/dev/null
	@set -o pipefail; ./modern/target/debug/geosat_modern < legacy/tests/golden/$(VECTOR).tlm \
	  | grep -n "SCID=\|UTC \|SSP LAT" | sed -n '1,9p'
	@echo
	@echo "The clock moves. The spacecraft does not. That is the bug --"
	@echo "reproduced exactly, on purpose, and NOT fixed."

# ~5 min. The loop runs in CI, as a reviewable pull request.
# The fence is the whole argument in beat 4b, so show it rather than describe
# it. allowed-files is what the pull request is checked against.
beat4b:
	@clear
	@echo "== what the implement agent is allowed to change =="
	@echo
	@sed -n '/^safe-outputs:/,/^---/p' \
	    .github/workflows/modernization-implement.md | sed '$$d' | sed 's/^/  /'
	@echo
	@echo "  legacy/src (the oracle), legacy/tests (the evidence),"
	@echo "  modern/tests (the judge) are all absent from that list."

beat4:
	@clear
	@echo "== compiled agentic workflows =="
	@ls -1 .github/workflows/*.md | sed 's|.*/|  |'
	@echo
	@gh aw status || echo "  (offline -- see demo/artifacts/)"

# ~2 min. A green suite means nothing until it has been shown to go red.
beat5:
	@clear
	@./tools/mutation-check.sh

# ---------------------------------------------------------------- housekeeping

# Restores ONLY the paths a demo run can mutate. It deliberately does not do
# `git checkout -- .`, which silently discards unrelated uncommitted work --
# that has already cost this repo one round of edits.
# Between runs. Every dispatch opens a new PR on a new branch, so without this
# you accumulate near-identical PRs and end up picking one out of a list on
# stage. Keeps the newest for the routine each beat actually demos.
prclean:
	@./tools/prclean.sh $(PRCLEAN_ARGS)

# Resolve and open the right PR by name, so you never scan a list live.
pr-plan:
	@./tools/openpr.sh plan

pr-port:
	@./tools/openpr.sh port

reset:
	@git checkout -- legacy/src modern/src modern/tests 2>/dev/null || true
	@$(MAKE) -C legacy clean >/dev/null 2>&1 || true
	@$(MAKE) -C legacy all >/dev/null 2>&1
	@rest=$$(git status --porcelain -- . ':!legacy/graphify-out' ':!legacy/src' ':!modern' | grep -v '^??' || true); \
	 if [ -n "$$rest" ]; then \
	   echo "reset -- mutation targets restored. Left alone (uncommitted, not mine to revert):"; \
	   echo "$$rest" | sed 's/^/  /'; \
	 else \
	   echo "reset -- repo is at stage-start state"; \
	 fi

clean:
	@$(MAKE) -C legacy clean
	@cd modern && cargo clean
	@rm -rf legacy/graphify-out
