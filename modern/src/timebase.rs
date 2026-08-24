//! GPS-to-UTC time conversion.
//!
//! Port of `TIMCNV` in `legacy/src/geosat.f:440`.
//!
//! `TIMCNV` backs out a hand-maintained leap-second offset to recover UTC
//! seconds-of-day, splits that into hours/minutes/seconds, then walks
//! forward year-by-year (and month-by-month) from the GPS epoch (1980 Jan 06)
//! to find the calendar date. All arithmetic in the legacy routine is
//! `INTEGER`, so this port uses `i64` throughout and Rust's `/` (which, like
//! FORTRAN integer division, truncates toward zero) to match exactly.

pub const GPS_EPOCH_YEAR: i64 = 1980;

/// Leap-second offset between GPS time and UTC.
///
/// A hand-maintained constant in the legacy source. Reproduce whatever the
/// legacy deck uses. Do not "correct" it -- changing it changes the output,
/// and the point of the port is to not change the output.
pub const LEAP_SECONDS: i64 = 18;

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

const MDAYS: [i64; 12] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/// Convert GPS seconds of epoch to UTC calendar fields.
///
/// Port of `TIMCNV` (`legacy/src/geosat.f:440`).
pub fn to_utc(gps_seconds: i64) -> UtcTime {
    // BACK OUT LEAP SECONDS TO REACH UTC
    let totsec = gps_seconds - LEAP_SECONDS;

    let mut ndays = totsec / 86400;
    let mut rem = totsec - (ndays * 86400);
    if rem < 0 {
        rem += 86400;
        ndays -= 1;
    }

    let utchr = rem / 3600;
    let utcmin = (rem - utchr * 3600) / 60;
    let utcsec = rem - utchr * 3600 - utcmin * 60;

    // WALK FORWARD FROM THE GPS EPOCH, 1980 JAN 06
    let mut yr = GPS_EPOCH_YEAR;
    ndays += 5;

    loop {
        let mut diny = 365;
        if yr % 4 == 0 && yr % 100 != 0 {
            diny = 366;
        }
        if yr % 400 == 0 {
            diny = 366;
        }
        if ndays < diny {
            break;
        }
        ndays -= diny;
        yr += 1;
    }

    let utcyr = yr;
    let utcdoy = ndays + 1;

    let mut mo = 1;
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

    let utcmon = mo;
    let utcday = ndays + 1;

    UtcTime {
        year: utcyr,
        month: utcmon,
        day: utcday,
        hour: utchr,
        minute: utcmin,
        second: utcsec,
        day_of_year: utcdoy,
    }
}
