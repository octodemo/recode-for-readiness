//! Engineering-unit conversion and limit screening.
//!
//! Port of `ENGCNV` and `LIMCHK` in `legacy/src/geosat.f`.
//!
//! Coefficients are the flight calibration set from the 1986 thermal-vacuum
//! campaign (cal report TV-86-09). Channel 3 uses the revised thermistor fit
//! from ECO 91-217; the original linear fit read 4 degC high at the cold end
//! and produced spurious red alarms during eclipse.
//!
//! Limits are the on-orbit set from flight operations handbook FOH-4021 rev C,
//! table 5-3. Channels with no meaningful limits (9 and 11) are given
//! wide-open values rather than being special-cased, because the original
//! display driver indexed this table directly and faulted on a short table.

pub const CHANNEL_COUNT: usize = 11;

pub const CHANNEL_NAMES: [&str; CHANNEL_COUNT] = [
    "BUSV", "BUSI", "BATT", "RWRP", "GYRX", "GYRY", "GYRZ", "PLTM", "XMTP", "RAGC", "SAAN",
];

pub const CHANNEL_UNITS: [&str; CHANNEL_COUNT] = [
    "VDC", "AMPS", "DEG C", "RPM", "DEG/S", "DEG/S", "DEG/S", "DEG C", "WATTS", "DBM", "DEG",
];

// EU = C0 + C1*raw + C2*raw*raw
const C0: [f32; CHANNEL_COUNT] = [0.0, 0.0, -55.0, 0.0, 0.0, 0.0, 0.0, -40.0, 0.0, -120.0, 0.0];

const C1: [f32; CHANNEL_COUNT] = [
    0.0012207, 0.0003052, 0.0025400, 0.5000000, 0.0019531, 0.0019531, 0.0019531, 0.0030518,
    0.0392157, 0.4705882, 1.0000000,
];

const C2: [f32; CHANNEL_COUNT] = [0.0, 0.0, -1.2e-8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

const RED_LOW: [f32; CHANNEL_COUNT] =
    [24.0, 0.0, -20.0, -6000.0, -8.0, -8.0, -8.0, -30.0, 0.0, -95.0, 0.0];
const YEL_LOW: [f32; CHANNEL_COUNT] =
    [26.0, 0.5, -10.0, -5000.0, -5.0, -5.0, -5.0, -20.0, 1.0, -90.0, 0.0];
const YEL_HIGH: [f32; CHANNEL_COUNT] =
    [32.5, 14.0, 35.0, 5000.0, 5.0, 5.0, 5.0, 45.0, 9.0, -55.0, 360.0];
const RED_HIGH: [f32; CHANNEL_COUNT] =
    [34.0, 16.0, 45.0, 6000.0, 8.0, 8.0, 8.0, 55.0, 10.0, -45.0, 360.0];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Alarm {
    Ok,
    YellowLow,
    YellowHigh,
    RedLow,
    RedHigh,
}

impl Alarm {
    /// The three-character status column the archive loader parses.
    pub fn text(self) -> &'static str {
        match self {
            Alarm::Ok => " OK",
            Alarm::YellowLow => " YL",
            Alarm::YellowHigh => " YH",
            Alarm::RedLow => " RL",
            Alarm::RedHigh => " RH",
        }
    }
}

/// Apply the per-channel calibration polynomial in single precision.
///
/// Every step is a separate `f32` operation, associating left to right exactly
/// as the FORTRAN expression does. See `precision` for why that matters.
pub fn convert(raw: &[i32; CHANNEL_COUNT]) -> [f32; CHANNEL_COUNT] {
    let mut eu = [0f32; CHANNEL_COUNT];

    for i in 0..CHANNEL_COUNT {
        let r = raw[i] as f32;
        let term1 = C1[i] * r;
        let term2 = C2[i] * r * r;
        eu[i] = C0[i] + term1 + term2;
    }

    // Solar array angle is already in degrees and wraps at 360.
    if eu[10] >= 360.0 {
        eu[10] -= 360.0;
    }

    eu
}

/// Screen engineering values against the on-orbit limit set.
pub fn screen(eu: &[f32; CHANNEL_COUNT]) -> [Alarm; CHANNEL_COUNT] {
    let mut status = [Alarm::Ok; CHANNEL_COUNT];

    for i in 0..CHANNEL_COUNT {
        let v = eu[i];
        status[i] = if v < RED_LOW[i] {
            Alarm::RedLow
        } else if v > RED_HIGH[i] {
            Alarm::RedHigh
        } else if v < YEL_LOW[i] {
            Alarm::YellowLow
        } else if v > YEL_HIGH[i] {
            Alarm::YellowHigh
        } else {
            Alarm::Ok
        };
    }

    status
}
