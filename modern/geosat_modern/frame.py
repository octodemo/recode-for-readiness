"""Telemetry frame decommutation.

Port of TLMDEC / RDFRM / HEXVAL in legacy/src/geosat.f.

Frame layout is ICD 4021-B table 6-2, reproduced in the legacy header. The
one non-obvious behaviour preserved here is channel 11: the solar array
angle is not decommutated from its own field, it is reconstructed from the
low nibble of byte 28 -- which is simultaneously the low byte of channel 8
(payload temperature). Those two channels are therefore coupled in the wire
format. See ECO 91-217.
"""
from dataclasses import dataclass
from typing import List, Optional

from .crc import crc16

SYNC_WORD = 0x1ACF
FRAME_LENGTH = 32
CHANNEL_COUNT = 11


class DecodeError(Exception):
    """Base class for frame-level decode failures."""

    code = 0


class SyncLoss(DecodeError):
    """Frame did not begin with the expected sync pattern."""

    code = 1


class CrcFailure(DecodeError):
    """Frame CRC did not match the computed value."""

    code = 2


@dataclass(frozen=True)
class Frame:
    """One decommutated telemetry frame."""

    scid: int
    apid: int
    frame_count: int
    gps_seconds: int
    raw: List[int]


def _u16(b: bytes, off: int) -> int:
    return (b[off] << 8) | b[off + 1]


def _i16(b: bytes, off: int) -> int:
    v = _u16(b, off)
    return v - 65536 if v > 32767 else v


def decode(frame: bytes) -> Frame:
    """Decommutate one 32-byte frame.

    Raises SyncLoss or CrcFailure, mirroring the IRC return codes of TLMDEC.
    """
    if len(frame) != FRAME_LENGTH:
        raise DecodeError("expected %d bytes, got %d" % (FRAME_LENGTH, len(frame)))

    if _u16(frame, 0) != SYNC_WORD:
        raise SyncLoss("sync pattern mismatch")

    if _u16(frame, 30) != crc16(frame[:30]):
        raise CrcFailure("crc mismatch")

    raw = [0] * CHANNEL_COUNT
    raw[0] = _u16(frame, 12)
    raw[1] = _u16(frame, 14)
    raw[2] = _u16(frame, 16)
    raw[3] = _i16(frame, 18)
    raw[4] = _i16(frame, 20)
    raw[5] = _i16(frame, 22)
    raw[6] = _i16(frame, 24)
    raw[7] = _u16(frame, 26)
    raw[8] = frame[28]
    raw[9] = frame[29]
    # Channel 11 shares byte 28 with the low half of channel 8. Not a bug --
    # the wire format really is packed this way. See ECO 91-217.
    raw[10] = (frame[27] & 0x0F) * 24

    return Frame(
        scid=frame[2],
        apid=frame[3],
        frame_count=int.from_bytes(frame[4:8], "big"),
        gps_seconds=int.from_bytes(frame[8:12], "big"),
        raw=raw,
    )


def parse_record(line: str) -> Optional[bytes]:
    """Parse one hex-encoded frame record.

    Returns None for operator comment records (leading '*') and blank
    records, matching RDFRM's skip behaviour, which the pass log format
    depends on.
    """
    if line.startswith("*"):
        return None
    if line[:2] == "  " or not line.strip():
        return None

    field = line[: FRAME_LENGTH * 2]
    if len(field) < FRAME_LENGTH * 2:
        raise ValueError("short record")
    try:
        return bytes.fromhex(field)
    except ValueError:
        raise ValueError("malformed record")
