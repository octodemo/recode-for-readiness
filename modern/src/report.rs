//! Pass summary rendering.
//!
//! Port of `REPORT` and the driver-level messages in `legacy/src/geosat.f`.
//!
//! The column layout is consumed by the downstream archive loader (ARCLOD),
//! which parses by fixed column position rather than by delimiter. Any change
//! to these field widths breaks the archive, so they are pinned by the
//! characterization suite.

use crate::calibration::{Alarm, CHANNEL_NAMES, CHANNEL_UNITS};
use crate::fortran::{fw, iw, iw_zero};
use crate::frame::Frame;
use crate::orbit::SubsatellitePoint;
use crate::timebase::UtcTime;

pub const FRAME_HEADER: &str = "---- GEOSAT TELEMETRY FRAME ----";
pub const TABLE_HEADER: &str = "CH NAME     RAW        EU  UNITS    ST";
pub const SUMMARY_HEADER: &str = "---- PASS SUMMARY ----";

pub const MSG_MALFORMED: &str = "*** MALFORMED RECORD SKIPPED";
pub const MSG_SYNC_LOSS: &str = "*** SYNC LOSS";

/// Render the CRC failure message.
///
/// `TLMDEC` returns before assigning `FRMCNT` when the CRC check fails, so the
/// value printed here is whatever the previous successfully decoded frame left
/// in the `/FRAME/` common block -- zero before the first good frame. That
/// staleness is reproduced deliberately; it is pinned by the characterization
/// vectors and is recorded as a modernization finding.
pub fn crc_failure(stale_frame_count: i64) -> String {
    format!("*** CRC FAILURE ON FRAME {}", iw(stale_frame_count, 10))
}

/// Render one decommutated frame as the legacy fixed-column block.
pub fn render_frame(
    frame: &Frame,
    eu: &[f32],
    status: &[Alarm],
    utc: &UtcTime,
    ssp: &SubsatellitePoint,
) -> Vec<String> {
    let mut lines = vec![
        FRAME_HEADER.to_string(),
        format!(
            "SCID={}  APID={}  FRAME={}",
            iw(frame.scid, 3),
            iw(frame.apid, 3),
            iw(frame.frame_count, 10)
        ),
        format!(
            "UTC {}-{}-{} {}:{}:{}  DOY={}",
            iw_zero(utc.year, 4, 4),
            iw_zero(utc.month, 2, 2),
            iw_zero(utc.day, 2, 2),
            iw_zero(utc.hour, 2, 2),
            iw_zero(utc.minute, 2, 2),
            iw_zero(utc.second, 2, 2),
            iw_zero(utc.day_of_year, 3, 3)
        ),
        format!(
            "SSP LAT={}  LON={}  ALT={}",
            fw(ssp.latitude_deg, 8, 3),
            fw(ssp.longitude_deg, 9, 3),
            fw(ssp.altitude_km, 7, 1)
        ),
        TABLE_HEADER.to_string(),
    ];

    for i in 0..CHANNEL_NAMES.len() {
        lines.push(format!(
            "{} {:<4} {} {} {:<8} {:>3}",
            iw((i + 1) as i64, 2),
            CHANNEL_NAMES[i],
            iw(frame.raw[i] as i64, 7),
            fw(eu[i], 9, 3),
            CHANNEL_UNITS[i],
            status[i].text()
        ));
    }

    lines
}

/// Render the end-of-pass summary block.
pub fn render_summary(good: i64, sync_losses: i64, crc_failures: i64, alarms: i64) -> Vec<String> {
    vec![
        SUMMARY_HEADER.to_string(),
        format!("FRAMES PROCESSED  {}", iw(good, 8)),
        format!("SYNC LOSSES       {}", iw(sync_losses, 8)),
        format!("CRC FAILURES      {}", iw(crc_failures, 8)),
        format!("LIMIT VIOLATIONS  {}", iw(alarms, 8)),
    ]
}
