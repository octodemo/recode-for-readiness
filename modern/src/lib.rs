//! Modernized GEOSAT telemetry processor.
//!
//! A behaviour-preserving port of the 1987 FORTRAN deck in
//! `legacy/src/geosat.f`. Parity with the original is enforced by the
//! characterization suite in `modern/tests`, which diffs this implementation
//! against the compiled legacy binary over the golden vectors in
//! `legacy/tests/golden`.
//!
//! Nothing here is an improvement on the original. Where the 1987 deck loses
//! precision, mis-scales a channel, or prints a stale counter, this port does
//! the same thing, on purpose, and says so in a comment. Fixing any of it is
//! a mission-assurance decision with its own review and its own updated
//! vectors -- not a refactor.

#![forbid(unsafe_code)]

pub mod calibration;
pub mod crc;
pub mod fortran;
pub mod frame;
pub mod orbit;
pub mod pipeline;
pub mod precision;
pub mod report;
pub mod timebase;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
