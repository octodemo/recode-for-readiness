//! Single-precision arithmetic contract.
//!
//! The legacy GEOSAT processor declares every engineering value as FORTRAN
//! `REAL(4)`. Reproducing its output byte for byte therefore requires doing
//! the arithmetic in IEEE-754 binary32.
//!
//! In the Python port this module was an emulation layer: every intermediate
//! result had to be packed through `struct` to force it back down to binary32,
//! because Python has no single-precision float. Rust has `f32` as a first
//! class type, so ordinary `+ - * /` on `f32` *is* the 1987 numeric model,
//! correctly rounded per operation. The emulation is gone.
//!
//! Two properties matter and neither is accidental:
//!
//! 1. Rust never contracts `a * b + c` into a fused multiply-add on its own.
//!    Contraction would compute the product at higher precision and change
//!    the result. This is what the legacy Makefile buys with
//!    `-ffp-contract=off` on the gfortran side; here it is the language
//!    guarantee.
//! 2. Association is explicit. `a * b * c` is `(a * b) * c`, evaluated left to
//!    right with a rounding at each step, which is what the FORTRAN
//!    expressions do. Rounding only at the end of an expression is *not*
//!    equivalent -- it produces a double-rounded result that diverges from the
//!    original once the operands are large.
//!
//! What remains here are the transcendentals, and this is the one place the
//! parity claim is narrower than it looks. FORTRAN `REAL(4)` intrinsics
//! resolve to the platform's `sinf`/`cosf`/`asinf`/`atan2f`. On the macOS
//! target these are defined as the double-precision routine rounded once to
//! binary32, which is exactly what the shims below do -- and that is *why*
//! byte parity holds against the compiled deck. glibc, by contrast, ships
//! properly-rounded single-precision routines that can differ from this by up
//! to 1 ULP at some inputs.
//!
//! So: the arithmetic parity above is a language guarantee. The transcendental
//! parity is an empirical result on pinned vectors and a pinned target. Anyone
//! rebuilding this for a different ground station re-runs the characterization
//! suite there before trusting it. Do not state it more strongly than that.

/// `sin(x)` evaluated in double precision, rounded once to binary32.
pub fn sin(x: f32) -> f32 {
    (x as f64).sin() as f32
}

/// `cos(x)` evaluated in double precision, rounded once to binary32.
pub fn cos(x: f32) -> f32 {
    (x as f64).cos() as f32
}

/// `asin(x)` evaluated in double precision, rounded once to binary32.
pub fn asin(x: f32) -> f32 {
    (x as f64).asin() as f32
}

/// `atan2(y, x)` evaluated in double precision, rounded once to binary32.
pub fn atan2(y: f32, x: f32) -> f32 {
    (y as f64).atan2(x as f64) as f32
}

/// `sqrt(x)` evaluated in double precision, rounded once to binary32.
pub fn sqrt(x: f32) -> f32 {
    (x as f64).sqrt() as f32
}

/// FORTRAN `AMOD` -- truncated remainder, exact for binary32 operands.
pub fn fmod(x: f32, y: f32) -> f32 {
    x % y
}
