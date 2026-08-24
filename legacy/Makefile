# GEOSAT Telemetry Processor -- legacy build
#
# The original build was a DCL command procedure on VAX/VMS (GEOSAT.COM).
# This Makefile is the 1994 Alpha/OSF port, minimally updated for gfortran.
# The entire flight chain is one compilation unit; see the header in
# src/geosat.f for why.

FC      = gfortran
FFLAGS  = -std=legacy -ffixed-form -fno-automatic -O1 -ffp-contract=off -w

SRCDIR  = src
BUILD   = build
BIN     = $(BUILD)/geosat

.PHONY: all clean check

all: $(BIN)

$(BIN): $(SRCDIR)/geosat.f $(SRCDIR)/geosat.inc
	@mkdir -p $(BUILD)
	$(FC) $(FFLAGS) -I$(SRCDIR) -o $@ $(SRCDIR)/geosat.f

check: $(BIN)
	@fail=0; \
	for v in pass01 pass02 pass03 edge01; do \
	  ./$(BIN) < tests/golden/$$v.tlm > /tmp/geosat_$$v.actual; \
	  if diff -q tests/expected/$$v.out /tmp/geosat_$$v.actual >/dev/null; then \
	    echo "  PASS  $$v"; \
	  else \
	    echo "  FAIL  $$v"; fail=1; \
	  fi; \
	done; \
	exit $$fail

clean:
	rm -rf $(BUILD)
