//! GPS-to-UTC time conversion.
//!
//! Port of `TIMCNV` in `legacy/src/geosat.f`.
//!
//! The GPS epoch is 1980-01-06 00:00:00 UTC. The leap-second offset is a
//! hand-maintained constant in the legacy source, last updated 2016-12-31.
//! It is reproduced here as a constant rather than sourced from a leap-second
//! table on purpose: changing it would change the output, and the point of
//! this port is to not change the output.
//!
//! Recorded for the modernization backlog, not fixed here: `LEAP_SECONDS` is
//! stale for any epoch after 2016-12-31. Replacing it with a maintained table
//! is a behavioural change and must be its own reviewed change with its own
//! updated golden vectors.

pub const GPS_EPOCH_YEAR: i64 = 1980;
pub const LEAP_SECONDS: i64 = 18;

const MDAYS: [i64; 12] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

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

/// Leap-year test as written at `geosat.f:481-482`: divisible by 4 and not by
/// 100, unless also divisible by 400. Written as two separate `IF`s to match
/// the FORTRAN control flow rather than collapsing into one boolean
/// expression.
fn diny(year: i64) -> i64 {
    let mut diny = 365;
    if year % 4 == 0 && year % 100 != 0 {
        diny = 366;
    }
    if year % 400 == 0 {
        diny = 366;
    }
    diny
}

/// Convert GPS seconds of epoch to UTC calendar fields.
///
/// Port of `TIMCNV` in `legacy/src/geosat.f:440-509`.
pub fn to_utc(gps_seconds: i64) -> UtcTime {
    // BACK OUT LEAP SECONDS TO REACH UTC (geosat.f:462).
    let totsec = gps_seconds - LEAP_SECONDS;

    // FORTRAN integer division truncates toward zero; NDAYS/REM are then
    // corrected below to land on the floor-divided result, exactly as the
    // legacy deck does at geosat.f:464-469.
    let mut ndays = totsec / 86400;
    let mut rem = totsec - ndays * 86400;
    if rem < 0 {
        rem += 86400;
        ndays -= 1;
    }

    let utchr = rem / 3600;
    let utcmin = (rem - utchr * 3600) / 60;
    let utcsec = rem - utchr * 3600 - utcmin * 60;

    // WALK FORWARD FROM THE GPS EPOCH, 1980 JAN 06 (geosat.f:475-486).
    let mut yr = GPS_EPOCH_YEAR;
    ndays += 5;

    loop {
        let length = diny(yr);
        if ndays < length {
            break;
        }
        ndays -= length;
        yr += 1;
    }

    let utcyr = yr;
    let utcdoy = ndays + 1;

    // Walk the day count through the months (geosat.f:492-502).
    let mut mo = 1i64;
    loop {
        let mut dim = MDAYS[(mo - 1) as usize];
        if mo == 2 {
            if yr % 4 == 0 && yr % 100 != 0 {
                dim = 29;
            }
            if yr % 400 == 0 {
                dim = 29;
            }
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
