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

fn is_leap(year: i64) -> bool {
    if year % 400 == 0 {
        return true;
    }
    if year % 100 == 0 {
        return false;
    }
    year % 4 == 0
}

/// Convert GPS seconds of epoch to UTC calendar fields.
pub fn to_utc(gps_seconds: i64) -> UtcTime {
    let total = gps_seconds - LEAP_SECONDS;

    // Floor division, matching Python's `divmod`. The legacy deck only ever
    // sees post-epoch timestamps, but flooring keeps the two ports identical
    // rather than identical-for-the-inputs-we-happened-to-test.
    let mut days = total.div_euclid(86400);
    let remainder = total.rem_euclid(86400);

    let hour = remainder.div_euclid(3600);
    let rem = remainder.rem_euclid(3600);
    let minute = rem.div_euclid(60);
    let second = rem.rem_euclid(60);

    // Walk forward from the GPS epoch, 1980-01-06.
    let mut year = GPS_EPOCH_YEAR;
    days += 5;

    loop {
        let length = if is_leap(year) { 366 } else { 365 };
        if days < length {
            break;
        }
        days -= length;
        year += 1;
    }

    let day_of_year = days + 1;

    let mut month = 1i64;
    loop {
        let mut length = MONTH_DAYS[(month - 1) as usize];
        if month == 2 && is_leap(year) {
            length = 29;
        }
        if days < length {
            break;
        }
        days -= length;
        month += 1;
    }

    UtcTime {
        year,
        month,
        day: days + 1,
        hour,
        minute,
        second,
        day_of_year,
    }
}
