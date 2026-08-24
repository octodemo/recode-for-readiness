"""CRC-16 frame integrity check.

Port of the CRCCHK function in legacy/src/geosat.f.

CCITT CRC-16: polynomial 0x1021, initial value 0xFFFF, no final XOR,
most-significant-bit first. Per ICD 4021-B section 6.7.

The legacy comment notes that a 256-entry lookup table was lost in the 1994
VAX-to-Alpha port, leaving the bit-serial version. This port keeps the
bit-serial form so that the two implementations can be compared line by line
during review; a table-driven version would be faster but would obscure the
correspondence.
"""

POLYNOMIAL = 0x1021
INITIAL = 0xFFFF


def crc16(data: bytes) -> int:
    """Compute the CCITT CRC-16 over `data`."""
    crc = INITIAL
    for byte in data:
        crc ^= (byte << 8) & 0xFFFF
        for _ in range(8):
            msb = crc & 0x8000
            crc = (crc << 1) & 0xFFFF
            if msb:
                crc ^= POLYNOMIAL
    return crc & 0xFFFF
