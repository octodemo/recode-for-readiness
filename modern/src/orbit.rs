//! Quick-look subsatellite point.
//!
//! Port of `ORBPRP` in `legacy/src/geosat.f`.
//!
//! This is the quick-look propagator only. It assumes a circular orbit at the
//! nominal mission altitude and ignores J2, drag, and all maneuver history.
//! The precision ephemeris is produced by the FDF and delivered separately.
//! Per memo GS-89-112 this routine must not be used for any pointing or
//! conjunction product.
//!
//! Elements are frozen at the epoch below because the element loader was never
//! ported off the VAX.
//!
//! # KNOWN DEFECT -- PRESERVED DELIBERATELY
//!
//! `dt` is computed and carried in single precision. For current epochs it is
//! on the order of 7.3e8 seconds, which exceeds the ~7 significant decimal
//! digits binary32 provides. The low bits of the time delta are therefore
//! discarded, and the propagated subsatellite point does not change between
//! telemetry frames four seconds apart.
//!
//! This port reproduces that behaviour exactly, because the characterization
//! suite pins current output. It is recorded as a finding for the
//! modernization backlog rather than silently corrected: changing it changes
//! every SSP value the archive has ever recorded, and that is a
//! mission-assurance decision, not a refactoring decision.

use crate::precision::{asin, atan2, cos, fmod, sin, sqrt};

pub const PI: f32 = 3.14159265;
pub const TWO_PI: f32 = 2.0 * PI;
pub const EARTH_RADIUS_KM: f32 = 6378.137;
pub const MU: f32 = 398600.4418;

pub const ELEMENT_ALTITUDE_KM: f32 = 785.0;
pub const ELEMENT_INCLINATION_DEG: f32 = 98.6;
pub const ELEMENT_RAAN_DEG: f32 = 142.35;
pub const ELEMENT_EPOCH_GPS: i64 = 630720000;

pub const EARTH_ROTATION_DEG_PER_DAY: f32 = 360.985647;

const DEG: f32 = 180.0;
const FULL_TURN: f32 = 360.0;
const SECONDS_PER_DAY: f32 = 86400.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SubsatellitePoint {
    pub latitude_deg: f32,
    pub longitude_deg: f32,
    pub altitude_km: f32,
}

/// `degrees * PI / 180.0`, associating left to right as FORTRAN does.
fn rad(degrees: f32) -> f32 {
    degrees * PI / DEG
}

/// `radians * 180.0 / PI`, associating left to right as FORTRAN does.
fn deg(radians: f32) -> f32 {
    radians * DEG / PI
}

/// Propagate the quick-look subsatellite point for a GPS timestamp.
pub fn propagate(gps_seconds: i64) -> SubsatellitePoint {
    let a = EARTH_RADIUS_KM + ELEMENT_ALTITUDE_KM;

    // PERIOD = 2.0 * PI * SQRT((A * A * A) / MU)
    let a_cubed = a * a * a;
    let period = TWO_PI * sqrt(a_cubed / MU);

    // Single precision, deliberately. See the KNOWN DEFECT note above.
    let dt = (gps_seconds - ELEMENT_EPOCH_GPS) as f32;

    // U = 2.0 * PI * (DT / PERIOD);  ARGLAT = AMOD(U, 2.0 * PI)
    let u = TWO_PI * (dt / period);
    let arg_lat = fmod(u, TWO_PI);

    let inc_rad = rad(ELEMENT_INCLINATION_DEG);
    let sin_i = sin(inc_rad);

    // XLAT = ASIN(SINI * SIN(ARGLAT)) * 180.0 / PI
    let latitude = deg(asin(sin_i * sin(arg_lat)));

    // RATE = 360.985647 / 86400.0;  LONASC = ELRAAN - RATE * DT
    let rate = EARTH_ROTATION_DEG_PER_DAY / SECONDS_PER_DAY;
    let lon_ascending = ELEMENT_RAAN_DEG - rate * dt;

    // XLON = LONASC + ATAN2(COS(ELINC)*SIN(ARGLAT), COS(ARGLAT)) * 180.0 / PI
    let in_track = deg(atan2(cos(inc_rad) * sin(arg_lat), cos(arg_lat)));

    let mut longitude = lon_ascending + in_track;
    longitude = fmod(longitude, FULL_TURN);
    if longitude > 180.0 {
        longitude -= FULL_TURN;
    }
    if longitude < -180.0 {
        longitude += FULL_TURN;
    }

    SubsatellitePoint {
        latitude_deg: latitude,
        longitude_deg: longitude,
        altitude_km: ELEMENT_ALTITUDE_KM,
    }
}
