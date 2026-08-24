//! Unit tests for the individually portable pieces of the pipeline.
//!
//! These pin behaviour that the characterization vectors happen to cover only
//! incidentally -- in particular the edge cases that a refactor is most likely
//! to "clean up" and thereby break.

use geosat_modern::calibration::{convert, screen, Alarm, CHANNEL_COUNT};
use geosat_modern::crc::crc16;
use geosat_modern::fortran::{fw, iw, iw_zero};
use geosat_modern::frame::{decode, parse_record, DecodeError, ParseError};
use geosat_modern::orbit::propagate;
use geosat_modern::timebase::to_utc;

/// Build a well-formed frame with a correct CRC.
fn build_frame(scid: u8, frame_count: u32, gps_seconds: u32, pltm: u16) -> Vec<u8> {
    let mut body = vec![0u8; 32];
    body[0..2].copy_from_slice(&0x1ACFu16.to_be_bytes());
    body[2] = scid;
    body[3] = 7;
    body[4..8].copy_from_slice(&frame_count.to_be_bytes());
    body[8..12].copy_from_slice(&gps_seconds.to_be_bytes());
    body[26..28].copy_from_slice(&pltm.to_be_bytes());
    let crc = crc16(&body[..30]);
    body[30..32].copy_from_slice(&crc.to_be_bytes());
    body
}

fn default_frame() -> Vec<u8> {
    build_frame(42, 1234, 1356998418, 19000)
}

fn raw_with(index: usize, value: i32) -> [i32; CHANNEL_COUNT] {
    let mut raw = [0i32; CHANNEL_COUNT];
    raw[index] = value;
    raw
}

fn assert_close(actual: f32, expected: f32, places: i32) {
    let tolerance = 0.5 * 10f32.powi(-places);
    assert!(
        (actual - expected).abs() <= tolerance,
        "expected {} within {} of {}",
        actual,
        tolerance,
        expected
    );
}

// ---------------------------------------------------------------- crc

#[test]
fn crc_matches_the_known_ccitt_vector() {
    // CCITT CRC-16 of "123456789" with init 0xFFFF, no final xor.
    assert_eq!(crc16(b"123456789"), 0x29B1);
}

#[test]
fn crc_of_empty_input_is_the_initial_value() {
    assert_eq!(crc16(b""), 0xFFFF);
}

// ---------------------------------------------------------------- formatting

#[test]
fn real_that_fits_is_right_justified() {
    assert_eq!(fw(1.5, 9, 3), "    1.500");
}

#[test]
fn real_overflow_fills_asterisks() {
    // -16384.000 is ten characters and cannot fit an F9.3 field.
    assert_eq!(fw(-16384.0, 9, 3), "*********");
}

#[test]
fn integer_overflow_fills_asterisks() {
    assert_eq!(iw(123456, 3), "***");
}

#[test]
fn zero_padded_integer() {
    assert_eq!(iw_zero(7, 3, 3), "007");
}

// ---------------------------------------------------------------- frame

#[test]
fn frame_roundtrip() {
    let frame = decode(&default_frame()).expect("well-formed frame must decode");
    assert_eq!(frame.scid, 42);
    assert_eq!(frame.frame_count, 1234);
}

#[test]
fn sync_loss_is_detected() {
    let mut body = default_frame();
    body[0] = 0x00;
    assert_eq!(decode(&body), Err(DecodeError::SyncLoss));
}

#[test]
fn crc_failure_is_detected() {
    let mut body = default_frame();
    body[31] ^= 0xFF;
    assert_eq!(decode(&body), Err(DecodeError::CrcFailure));
}

/// Solar array angle is reconstructed from the low nibble of byte 28.
///
/// Byte 28 is simultaneously the low byte of the payload temperature field, so
/// the two channels are coupled in the wire format. A refactor that gives
/// channel 11 its own field is a behaviour change.
#[test]
fn channel_11_is_coupled_to_channel_8_low_byte() {
    let frame = decode(&build_frame(42, 1234, 1356998418, 0x000F))
        .expect("well-formed frame must decode");
    assert_eq!(frame.raw[10], 15 * 24);
    assert_eq!(frame.raw[7], 0x000F);
}

#[test]
fn comment_and_blank_records_are_skipped() {
    assert_eq!(parse_record("* operator note"), Ok(None));
    assert_eq!(parse_record(""), Ok(None));
}

#[test]
fn malformed_record_is_rejected() {
    let line = "Z".repeat(64);
    assert_eq!(parse_record(&line), Err(ParseError::Malformed));
}

#[test]
fn short_record_is_rejected() {
    assert_eq!(parse_record("1ACF"), Err(ParseError::Short));
}

// ---------------------------------------------------------------- timebase

#[test]
fn gps_epoch_converts_to_1980_01_06() {
    // Leap seconds back out to exactly the epoch.
    let utc = to_utc(18);
    assert_eq!((utc.year, utc.month, utc.day), (1980, 1, 6));
}

#[test]
fn leap_year_day_of_year() {
    let utc = to_utc(1356998418);
    assert_eq!(utc.day_of_year, 6);
    assert_eq!(utc.year, 2023);
}

// ---------------------------------------------------------------- calibration

#[test]
fn battery_uses_the_quadratic_thermistor_fit() {
    let eu = convert(&raw_with(2, 25000));
    assert_close(eu[2], 1.0, 3);
}

#[test]
fn red_low_screening() {
    let eu = convert(&[0i32; CHANNEL_COUNT]);
    let status = screen(&eu);
    assert_eq!(status[0], Alarm::RedLow);
}

#[test]
fn solar_array_angle_wraps_at_360() {
    let eu = convert(&raw_with(10, 400));
    assert_close(eu[10], 40.0, 3);
}

// ---------------------------------------------------------------- orbit

/// Frames four seconds apart must propagate to the same subsatellite point.
///
/// This is the known single-precision time-overflow defect. It is pinned
/// deliberately: if this test starts failing, someone has changed the
/// propagator's numerical behaviour, which changes every archived
/// subsatellite point and is a mission-assurance decision.
#[test]
fn single_precision_defect_is_preserved() {
    let first = propagate(1356998418);
    let second = propagate(1356998422);
    assert_eq!(first.latitude_deg, second.latitude_deg);
    assert_eq!(first.longitude_deg, second.longitude_deg);
}

#[test]
fn longitude_is_wrapped() {
    let ssp = propagate(1356998418);
    assert!(ssp.longitude_deg >= -180.0);
    assert!(ssp.longitude_deg <= 180.0);
}
