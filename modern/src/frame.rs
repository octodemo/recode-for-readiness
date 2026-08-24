//! Telemetry frame decommutation.
//!
//! Port of `TLMDEC` / `RDFRM` / `HEXVAL` in `legacy/src/geosat.f`.
//!
//! Frame layout is ICD 4021-B table 6-2, reproduced in the legacy header. The
//! one non-obvious behaviour preserved here is channel 11: the solar array
//! angle is not decommutated from its own field, it is reconstructed from the
//! low nibble of byte 28 -- which is simultaneously the low byte of channel 8
//! (payload temperature). Those two channels are therefore coupled in the wire
//! format. See ECO 91-217.

use crate::crc::crc16;

pub const SYNC_WORD: u16 = 0x1ACF;
pub const FRAME_LENGTH: usize = 32;
pub const CHANNEL_COUNT: usize = 11;

/// Frame-level decode failures, mirroring the `IRC` return codes of `TLMDEC`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeError {
    /// Record was not exactly `FRAME_LENGTH` bytes.
    Length(usize),
    /// Frame did not begin with the expected sync pattern. `IRC = 1`.
    SyncLoss,
    /// Frame CRC did not match the computed value. `IRC = 2`.
    CrcFailure,
}

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DecodeError::Length(n) => {
                write!(f, "expected {} bytes, got {}", FRAME_LENGTH, n)
            }
            DecodeError::SyncLoss => write!(f, "sync pattern mismatch"),
            DecodeError::CrcFailure => write!(f, "crc mismatch"),
        }
    }
}

impl std::error::Error for DecodeError {}

/// Failures parsing one hex-encoded frame record.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParseError {
    Short,
    Malformed,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::Short => write!(f, "short record"),
            ParseError::Malformed => write!(f, "malformed record"),
        }
    }
}

impl std::error::Error for ParseError {}

/// One decommutated telemetry frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub scid: i64,
    pub apid: i64,
    pub frame_count: i64,
    pub gps_seconds: i64,
    pub raw: [i32; CHANNEL_COUNT],
}

fn u16_at(b: &[u8], off: usize) -> i32 {
    ((b[off] as i32) << 8) | (b[off + 1] as i32)
}

fn i16_at(b: &[u8], off: usize) -> i32 {
    let v = u16_at(b, off);
    if v > 32767 {
        v - 65536
    } else {
        v
    }
}

fn u32_at(b: &[u8], off: usize) -> i64 {
    ((b[off] as i64) << 24)
        | ((b[off + 1] as i64) << 16)
        | ((b[off + 2] as i64) << 8)
        | (b[off + 3] as i64)
}

/// Decommutate one 32-byte frame.
pub fn decode(frame: &[u8]) -> Result<Frame, DecodeError> {
    if frame.len() != FRAME_LENGTH {
        return Err(DecodeError::Length(frame.len()));
    }

    if u16_at(frame, 0) as u16 != SYNC_WORD {
        return Err(DecodeError::SyncLoss);
    }

    if u16_at(frame, 30) as u16 != crc16(&frame[..30]) {
        return Err(DecodeError::CrcFailure);
    }

    let mut raw = [0i32; CHANNEL_COUNT];
    raw[0] = u16_at(frame, 12);
    raw[1] = u16_at(frame, 14);
    raw[2] = u16_at(frame, 16);
    raw[3] = i16_at(frame, 18);
    raw[4] = i16_at(frame, 20);
    raw[5] = i16_at(frame, 22);
    raw[6] = i16_at(frame, 24);
    raw[7] = u16_at(frame, 26);
    raw[8] = frame[28] as i32;
    raw[9] = frame[29] as i32;
    // Channel 11 shares byte 28 with the low half of channel 8. Not a bug --
    // the wire format really is packed this way. See ECO 91-217.
    raw[10] = ((frame[27] & 0x0F) as i32) * 24;

    Ok(Frame {
        scid: frame[2] as i64,
        apid: frame[3] as i64,
        frame_count: u32_at(frame, 4),
        gps_seconds: u32_at(frame, 8),
        raw,
    })
}

/// Decode an ASCII hex string, skipping spaces, as Python's `bytes.fromhex` does.
fn from_hex(field: &str) -> Result<Vec<u8>, ParseError> {
    let digits: Vec<char> = field.chars().filter(|c| *c != ' ').collect();
    if digits.len() % 2 != 0 {
        return Err(ParseError::Malformed);
    }
    let mut out = Vec::with_capacity(digits.len() / 2);
    for pair in digits.chunks(2) {
        let hi = pair[0].to_digit(16).ok_or(ParseError::Malformed)?;
        let lo = pair[1].to_digit(16).ok_or(ParseError::Malformed)?;
        out.push(((hi << 4) | lo) as u8);
    }
    Ok(out)
}

/// Parse one hex-encoded frame record.
///
/// Returns `Ok(None)` for operator comment records (leading `*`) and blank
/// records, matching `RDFRM`'s skip behaviour, which the pass log format
/// depends on.
pub fn parse_record(line: &str) -> Result<Option<Vec<u8>>, ParseError> {
    if line.starts_with('*') {
        return Ok(None);
    }
    if line.starts_with("  ") || line.trim().is_empty() {
        return Ok(None);
    }

    let field: String = line.chars().take(FRAME_LENGTH * 2).collect();
    if field.chars().count() < FRAME_LENGTH * 2 {
        return Err(ParseError::Short);
    }

    from_hex(&field).map(Some)
}
