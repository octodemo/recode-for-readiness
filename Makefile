# Recode for Readiness -- demo driver
#
# Every target here is something run on stage or immediately before it.
# Nothing in this file requires the network except `push` and `beat4`.

SHELL := /usr/bin/env bash

# Never write bytecode. A stale .pyc left by a reverted mutation is invisible
# and will make the parity suite lie. See tools/mutation-check.sh.
export PYTHONDONTWRITEBYTECODE := 1
GRAPH := legacy/graphify-out/graph.json

.PHONY: help preflight rehearse legacy graph offline-proof parity mutants \
        workflows beat1 beat2 beat3 beat4 beat5 reset clean

help:
	@echo ""
	@echo "  Recode for Readiness -- GEOSAT telemetry processor"
	@echo ""
	@echo "  Before the room:"
	@echo "    make card           print the one-page podium cheat sheet"
	@echo "    make preflight      check every dependency, name what is missing"
	@echo "    make rehearse       run every offline beat end to end"
	@echo "    make reset          return the repo to its stage-start state"
	@echo ""
	@echo "  On stage:"
	@echo "    make beat1          the deck still runs, and nobody knows why"
	@echo "    make beat2          comprehension, in-boundary, no model"
	@echo "    make beat3          characterize, port, prove byte parity"
	@echo "    make beat4          hand the loop to an agent, in CI"
	@echo "    make beat5          prove the tests can fail"
	@echo ""
	@echo "  Parts:"
	@echo "    make legacy         build and run the 1987 FORTRAN deck"
	@echo "    make graph          build the knowledge graph"
	@echo "    make offline-proof  rebuild the graph with egress blackholed"
	@echo "    make parity         characterization + unit suite"
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

$(GRAPH):
	@graphify update legacy

graph: $(GRAPH)
	@python3 -c "import json;g=json.load(open('$(GRAPH)'));print('%d nodes, %d edges'%(len(g['nodes']),len(g['links'])))"

offline-proof:
	@./tools/offline-proof.sh

parity:
	@cd modern && python3 -m unittest discover -s tests -t .

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

# ~5 min. Pin the behaviour, port it, prove it did not move.
beat3:
	@clear
	@echo "== byte-for-byte against the 1987 binary =="
	@cd modern && python3 -m unittest discover -s tests -t . -v 2>&1 | tail -20

# ~5 min. The loop runs in CI, as a reviewable pull request.
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
reset:
	@git checkout -- legacy/src modern/geosat_modern modern/tests 2>/dev/null || true
	@$(MAKE) -C legacy clean >/dev/null 2>&1 || true
	@find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
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
	@rm -rf legacy/graphify-out
	@find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
