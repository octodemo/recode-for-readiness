"""Modernized GEOSAT telemetry processor.

A behaviour-preserving port of the 1987 FORTRAN deck in legacy/src/geosat.f.
Parity with the original is enforced by the characterization suite in
modern/tests, which diffs this implementation against the compiled legacy
binary over the golden vectors in legacy/tests/golden.
"""

__version__ = "0.1.0"
