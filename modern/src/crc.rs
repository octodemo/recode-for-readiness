//! CRC-16 frame integrity check.
//!
//! Port of the `CRCCHK` function in `legacy/src/geosat.f`.
//!
//! CCITT CRC-16: polynomial 0x1021, initial value 0xFFFF, no final XOR,
//! most-significant-bit first. Per ICD 4021-B section 6.7.
//!
//! The legacy comment notes that a 256-entry lookup table was lost in the 1994
//! VAX-to-Alpha port, leaving the bit-serial version. This port keeps the
//! bit-serial form so that the two implementations can be compared line by
//! line during review; a table-driven version would be faster but would
//! obscure the correspondence.

pub const POLYNOMIAL: u16 = 0x1021;
pub const INITIAL: u16 = 0xFFFF;

/// Compute the CCITT CRC-16 over `data`.
pub fn crc16(data: &[u8]) -> u16 {
    let mut crc = INITIAL;
    for &byte in data {
        crc ^= (byte as u16) << 8;
        for _ in 0..8 {
            let msb = crc & 0x8000;
            crc <<= 1;
            if msb != 0 {
                crc ^= POLYNOMIAL;
            }
        }
    }
    crc
}
