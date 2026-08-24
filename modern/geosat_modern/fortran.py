"""FORTRAN edit-descriptor semantics.

The legacy report is written with FORMAT statements, and FORTRAN output
edit descriptors do not widen a field when the value does not fit. They fill
the field with asterisks instead.

This matters in practice, not just in theory: reaction-wheel channel 4 at its
negative rail converts to -16384.000, which is ten characters wide and cannot
fit the F9.3 field REPORT declares. The legacy binary emits '*********' and
the downstream archive loader (ARCLOD) reads that as "no value". Any port
that silently widens the column produces a different file and a different
archive record.
"""


def fw(value: float, width: int, decimals: int) -> str:
    """Format a real using FORTRAN Fw.d semantics, asterisk-filling on overflow."""
    text = "%*.*f" % (width, decimals, value)
    if len(text) > width:
        return "*" * width
    return text


def iw(value: int, width: int) -> str:
    """Format an integer using FORTRAN Iw semantics, asterisk-filling on overflow."""
    text = "%*d" % (width, value)
    if len(text) > width:
        return "*" * width
    return text


def iw_zero(value: int, width: int, digits: int) -> str:
    """Format an integer using FORTRAN Iw.d semantics (zero-padded minimum digits)."""
    text = "%0*d" % (digits, value)
    text = "%*s" % (width, text)
    if len(text) > width:
        return "*" * width
    return text
