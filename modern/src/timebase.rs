//! GPS-to-UTC time conversion.
//!
//! Port of `TIMCNV` in `legacy/src/geosat.f` (lines 440-509).
//!
//! `TIMCNV` converts GPS seconds of epoch into UTC calendar fields. The GPS
//! epoch is 1980 JAN 06 00:00:00 UTC (`geosat.f:431`). The leap second offset
//! is a hand maintained constant (`geosat.f:447-448`) that must be updated by
//! hand whenever IERS announces a new leap second; it is reproduced here as a
//! constant for the same reason -- the point of the port is to not change the
//! output.
//!
//! Recorded for the modernization backlog, not fixed here: `LEAP_SECONDS` is
//! stale for any epoch after 2016-12-31. Replacing it with a maintained table
//! is a behavioural change and must be its own reviewed change with its own
//! updated golden vectors.

pub const GPS_EPOCH_YEAR: i64 = 1980;
pub const LEAP_SECONDS: i64 = 18;

const MONTH_DAYS: [i64; 12] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UtcTime {
    pub year: i64,
    pub month: i64,
    pub day: i64,
    pub hour: i64,
    pub minute: i64,
    pub second: i64,
    pub day_of_year: i64,
}

/// Matches the leap-year test at `geosat.f:481-482` / `geosat.f:496-497`:
/// divisible by 4 and not by 100, OR divisible by 400.
fn is_leap(year: i64) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

/// Convert GPS seconds of epoch to UTC calendar fields (`TIMCNV`,
/// `geosat.f:440-509`).
pub fn to_utc(gps_seconds: i64) -> UtcTime {
    // BACK OUT LEAP SECONDS TO REACH UTC (geosat.f:462).
    let totsec = gps_seconds - LEAP_SECONDS;

    // FORTRAN integer division truncates toward zero (geosat.f:464-469).
    let mut ndays = totsec / 86400;
    let mut rem = totsec - (ndays * 86400);
    if rem < 0 {
        rem += 86400;
        ndays -= 1;
    }

    let utchr = rem / 3600;
    let utcmin = (rem - utchr * 3600) / 60;
    let utcsec = rem - utchr * 3600 - utcmin * 60;

    // WALK FORWARD FROM THE GPS EPOCH, 1980 JAN 06 (geosat.f:476-486).
    let mut yr = GPS_EPOCH_YEAR;
    ndays += 5;

    loop {
        let diny = if is_leap(yr) { 366 } else { 365 };
        if ndays < diny {
            break;
        }
        ndays -= diny;
        yr += 1;
    }

    let utcyr = yr;
    let utcdoy = ndays + 1;

    // MONTH WALK (geosat.f:492-502).
    let mut mo = 1i64;
    loop {
        let mut dim = MONTH_DAYS[(mo - 1) as usize];
        if mo == 2 && is_leap(yr) {
            dim = 29;
        }
        if ndays < dim {
            break;
        }
        ndays -= dim;
        mo += 1;
    }

    UtcTime {
        year: utcyr,
        month: mo,
        day: ndays + 1,
        hour: utchr,
        minute: utcmin,
        second: utcsec,
        day_of_year: utcdoy,
    }
}
