//! Telemetry processing pipeline.
//!
//! Port of the `PROGRAM GEOSAT` driver in `legacy/src/geosat.f`.
//!
//! The legacy driver is a read-decode-convert-screen-propagate-report loop
//! over standard input. This module keeps that shape but expresses it as a
//! pure function over an iterator of records, so the same pipeline can be
//! driven by the CLI and by the characterization tests without change.

use crate::calibration::{convert, screen, Alarm};
use crate::frame::{decode, parse_record, DecodeError};
use crate::orbit::propagate;
use crate::report as rpt;
use crate::timebase::to_utc;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PassStatistics {
    pub frames_processed: i64,
    pub sync_losses: i64,
    pub crc_failures: i64,
    pub limit_violations: i64,
}

#[derive(Debug, Clone, Default)]
pub struct PassResult {
    pub lines: Vec<String>,
    pub statistics: PassStatistics,
}

/// Run the telemetry processing chain over hex-encoded frame records.
///
/// A record that parses but is not `FRAME_LENGTH` bytes is a hard error, not a
/// skipped record -- the legacy driver has no path for it either.
pub fn process<'a, I>(records: I) -> Result<PassResult, DecodeError>
where
    I: IntoIterator<Item = &'a str>,
{
    let mut result = PassResult::default();

    // Mirrors the /FRAME/ common block: FRMCNT persists between frames and is
    // only updated once a frame passes both sync and CRC checks.
    let mut last_frame_count: i64 = 0;

    for line in records {
        let line = line.strip_suffix('\n').unwrap_or(line);

        let payload = match parse_record(line) {
            Ok(Some(bytes)) => bytes,
            Ok(None) => continue,
            Err(_) => {
                result.lines.push(rpt::MSG_MALFORMED.to_string());
                continue;
            }
        };

        let frame = match decode(&payload) {
            Ok(frame) => frame,
            Err(DecodeError::SyncLoss) => {
                result.statistics.sync_losses += 1;
                result.lines.push(rpt::MSG_SYNC_LOSS.to_string());
                continue;
            }
            Err(DecodeError::CrcFailure) => {
                result.statistics.crc_failures += 1;
                result.lines.push(rpt::crc_failure(last_frame_count));
                continue;
            }
            Err(other) => return Err(other),
        };

        last_frame_count = frame.frame_count;
        result.statistics.frames_processed += 1;

        let eu = convert(&frame.raw);
        let status = screen(&eu);
        result.statistics.limit_violations +=
            status.iter().filter(|s| **s != Alarm::Ok).count() as i64;

        let utc = to_utc(frame.gps_seconds);
        let ssp = propagate(frame.gps_seconds);

        result
            .lines
            .extend(rpt::render_frame(&frame, &eu, &status, &utc, &ssp));
    }

    let stats = result.statistics;
    result.lines.extend(rpt::render_summary(
        stats.frames_processed,
        stats.sync_losses,
        stats.crc_failures,
        stats.limit_violations,
    ));

    Ok(result)
}
