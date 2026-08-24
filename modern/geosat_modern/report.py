"""Pass summary rendering.

Port of REPORT and the driver-level messages in legacy/src/geosat.f.

The column layout is consumed by the downstream archive loader (ARCLOD),
which parses by fixed column position rather than by delimiter. Any change
to these field widths breaks the archive, so they are pinned by the
characterization suite.
"""
from typing import List

from .calibration import ALARM_TEXT, CHANNEL_NAMES, CHANNEL_UNITS, Alarm
from .fortran import fw, iw, iw_zero
from .frame import Frame
from .orbit import SubsatellitePoint
from .timebase import UtcTime

FRAME_HEADER = "---- GEOSAT TELEMETRY FRAME ----"
TABLE_HEADER = "CH NAME     RAW        EU  UNITS    ST"
SUMMARY_HEADER = "---- PASS SUMMARY ----"

MSG_MALFORMED = "*** MALFORMED RECORD SKIPPED"
MSG_SYNC_LOSS = "*** SYNC LOSS"


def crc_failure(stale_frame_count: int) -> str:
    """Render the CRC failure message.

    TLMDEC returns before assigning FRMCNT when the CRC check fails, so the
    value printed here is whatever the previous successfully decoded frame
    left in the /FRAME/ common block -- zero before the first good frame.
    That staleness is reproduced deliberately; it is pinned by the
    characterization vectors and is recorded as a modernization finding.
    """
    return "*** CRC FAILURE ON FRAME " + iw(stale_frame_count, 10)


def render_frame(
    frame: Frame,
    eu: List[float],
    status: List[Alarm],
    utc: UtcTime,
    ssp: SubsatellitePoint,
) -> List[str]:
    """Render one decommutated frame as the legacy fixed-column block."""
    lines = [
        FRAME_HEADER,
        "SCID=" + iw(frame.scid, 3) + "  APID=" + iw(frame.apid, 3)
        + "  FRAME=" + iw(frame.frame_count, 10),
        "UTC "
        + iw_zero(utc.year, 4, 4) + "-" + iw_zero(utc.month, 2, 2)
        + "-" + iw_zero(utc.day, 2, 2) + " " + iw_zero(utc.hour, 2, 2)
        + ":" + iw_zero(utc.minute, 2, 2) + ":" + iw_zero(utc.second, 2, 2)
        + "  DOY=" + iw_zero(utc.day_of_year, 3, 3),
        "SSP LAT=" + fw(ssp.latitude_deg, 8, 3)
        + "  LON=" + fw(ssp.longitude_deg, 9, 3)
        + "  ALT=" + fw(ssp.altitude_km, 7, 1),
        TABLE_HEADER,
    ]

    for i in range(len(CHANNEL_NAMES)):
        lines.append(
            iw(i + 1, 2)
            + " " + "%-4s" % CHANNEL_NAMES[i]
            + " " + iw(frame.raw[i], 7)
            + " " + fw(eu[i], 9, 3)
            + " " + "%-8s" % CHANNEL_UNITS[i]
            + " " + "%3s" % ALARM_TEXT[status[i]]
        )

    return lines


def render_summary(
    good: int, sync_losses: int, crc_failures: int, alarms: int
) -> List[str]:
    """Render the end-of-pass summary block."""
    return [
        SUMMARY_HEADER,
        "FRAMES PROCESSED  " + iw(good, 8),
        "SYNC LOSSES       " + iw(sync_losses, 8),
        "CRC FAILURES      " + iw(crc_failures, 8),
        "LIMIT VIOLATIONS  " + iw(alarms, 8),
    ]
