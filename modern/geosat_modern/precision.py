"""Single-precision helpers.

The legacy GEOSAT processor declares every engineering value as FORTRAN
REAL(4). Reproducing its output byte for byte therefore requires doing the
arithmetic in IEEE-754 binary32, not Python's native binary64.

`f32` rounds a Python float to the nearest binary32 value. Applying it after
each individual operation mirrors what gfortran emits when floating-point
contraction is disabled (-ffp-contract=off), which the legacy Makefile sets
explicitly so that the two implementations are comparable at all.

This is deliberately not "better math". Preserving the original precision --
including the places where it loses information -- is the whole point of a
characterization test.
"""
import struct

_PACK = struct.Struct("<f").pack
_UNPACK = struct.Struct("<f").unpack


def f32(x: float) -> float:
    """Round a float to IEEE-754 single precision."""
    return _UNPACK(_PACK(x))[0]
