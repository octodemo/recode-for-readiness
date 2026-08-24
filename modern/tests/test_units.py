"""Unit tests for the individually portable pieces of the pipeline.

These pin behaviour that the characterization vectors happen to cover only
incidentally -- in particular the edge cases that a refactor is most likely
to "clean up" and thereby break.
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from geosat_modern.calibration import Alarm, convert, screen  # noqa: E402
from geosat_modern.crc import crc16  # noqa: E402
from geosat_modern.fortran import fw, iw, iw_zero  # noqa: E402
from geosat_modern.frame import (  # noqa: E402
    CrcFailure,
    SyncLoss,
    decode,
    parse_record,
)
from geosat_modern.orbit import propagate  # noqa: E402
from geosat_modern.timebase import to_utc  # noqa: E402


def _build_frame(**overrides):
    """Build a well-formed frame with a correct CRC."""
    import struct

    body = bytearray(32)
    struct.pack_into(">H", body, 0, 0x1ACF)
    body[2] = overrides.get("scid", 42)
    body[3] = overrides.get("apid", 7)
    struct.pack_into(">I", body, 4, overrides.get("frame_count", 1234))
    struct.pack_into(">I", body, 8, overrides.get("gps_seconds", 1356998418))
    struct.pack_into(">H", body, 26, overrides.get("pltm", 19000))
    struct.pack_into(">H", body, 30, crc16(bytes(body[:30])))
    return bytes(body)


class CrcTest(unittest.TestCase):
    def test_known_vector(self):
        # CCITT CRC-16 of "123456789" with init 0xFFFF, no final xor.
        self.assertEqual(crc16(b"123456789"), 0x29B1)

    def test_empty_input_is_initial_value(self):
        self.assertEqual(crc16(b""), 0xFFFF)


class FortranFormatTest(unittest.TestCase):
    def test_real_fits(self):
        self.assertEqual(fw(1.5, 9, 3), "    1.500")

    def test_real_overflow_fills_asterisks(self):
        # -16384.000 is ten characters and cannot fit an F9.3 field.
        self.assertEqual(fw(-16384.0, 9, 3), "*********")

    def test_integer_overflow_fills_asterisks(self):
        self.assertEqual(iw(123456, 3), "***")

    def test_zero_padded_integer(self):
        self.assertEqual(iw_zero(7, 3, 3), "007")


class FrameTest(unittest.TestCase):
    def test_roundtrip(self):
        frame = decode(_build_frame())
        self.assertEqual(frame.scid, 42)
        self.assertEqual(frame.frame_count, 1234)

    def test_sync_loss(self):
        body = bytearray(_build_frame())
        body[0] = 0x00
        with self.assertRaises(SyncLoss):
            decode(bytes(body))

    def test_crc_failure(self):
        body = bytearray(_build_frame())
        body[31] ^= 0xFF
        with self.assertRaises(CrcFailure):
            decode(bytes(body))

    def test_channel_11_is_coupled_to_channel_8_low_byte(self):
        """Solar array angle is reconstructed from the low nibble of byte 28.

        Byte 28 is simultaneously the low byte of the payload temperature
        field, so the two channels are coupled in the wire format. A refactor
        that gives channel 11 its own field is a behaviour change.
        """
        frame = decode(_build_frame(pltm=0x000F))
        self.assertEqual(frame.raw[10], 15 * 24)
        self.assertEqual(frame.raw[7], 0x000F)

    def test_comment_records_are_skipped(self):
        self.assertIsNone(parse_record("* operator note"))
        self.assertIsNone(parse_record(""))

    def test_malformed_record_raises(self):
        with self.assertRaises(ValueError):
            parse_record("ZZ" * 32)


class TimebaseTest(unittest.TestCase):
    def test_gps_epoch(self):
        utc = to_utc(18)  # leap seconds back out to exactly the epoch
        self.assertEqual((utc.year, utc.month, utc.day), (1980, 1, 6))

    def test_leap_year_day_of_year(self):
        utc = to_utc(1356998418)
        self.assertEqual(utc.day_of_year, 6)
        self.assertEqual(utc.year, 2023)


class CalibrationTest(unittest.TestCase):
    def test_battery_uses_quadratic_fit(self):
        eu = convert([0] * 2 + [25000] + [0] * 8)
        self.assertAlmostEqual(eu[2], 1.0, places=3)

    def test_red_low_screening(self):
        eu = convert([0] * 11)
        status = screen(eu)
        self.assertEqual(status[0], Alarm.RED_LOW)

    def test_solar_array_angle_wraps(self):
        eu = convert([0] * 10 + [400])
        self.assertAlmostEqual(eu[10], 40.0, places=3)


class OrbitTest(unittest.TestCase):
    def test_single_precision_defect_is_preserved(self):
        """Frames four seconds apart must propagate to the same SSP.

        This is the known single-precision time-overflow defect. It is pinned
        deliberately: if this test starts failing, someone has changed the
        propagator's numerical behaviour, which changes every archived
        subsatellite point and is a mission-assurance decision.
        """
        first = propagate(1356998418)
        second = propagate(1356998422)
        self.assertEqual(first.latitude_deg, second.latitude_deg)
        self.assertEqual(first.longitude_deg, second.longitude_deg)

    def test_longitude_is_wrapped(self):
        ssp = propagate(1356998418)
        self.assertGreaterEqual(ssp.longitude_deg, -180.0)
        self.assertLessEqual(ssp.longitude_deg, 180.0)


if __name__ == "__main__":
    unittest.main()
