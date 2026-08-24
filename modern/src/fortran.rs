//! FORTRAN edit-descriptor semantics.
//!
//! The legacy report is written with `FORMAT` statements, and FORTRAN output
//! edit descriptors do not widen a field when the value does not fit. They
//! fill the field with asterisks instead.
//!
//! This matters in practice, not just in theory: reaction-wheel channel 4 at
//! its negative rail converts to -16384.000, which is ten characters wide and
//! cannot fit the `F9.3` field `REPORT` declares. The legacy binary emits
//! `*********` and the downstream archive loader (ARCLOD) reads that as
//! "no value". Any port that silently widens the column produces a different
//! file and a different archive record.

/// Format a real using FORTRAN `Fw.d` semantics, asterisk-filling on overflow.
pub fn fw(value: f32, width: usize, decimals: usize) -> String {
    let text = format!("{:>width$.decimals$}", value, width = width, decimals = decimals);
    if text.len() > width {
        return "*".repeat(width);
    }
    text
}

/// Format an integer using FORTRAN `Iw` semantics, asterisk-filling on overflow.
pub fn iw(value: i64, width: usize) -> String {
    let text = format!("{:>width$}", value, width = width);
    if text.len() > width {
        return "*".repeat(width);
    }
    text
}

/// Format an integer using FORTRAN `Iw.d` semantics (zero-padded minimum digits).
pub fn iw_zero(value: i64, width: usize, digits: usize) -> String {
    let padded = format!("{:0digits$}", value, digits = digits);
    let text = format!("{:>width$}", padded, width = width);
    if text.len() > width {
        return "*".repeat(width);
    }
    text
}
