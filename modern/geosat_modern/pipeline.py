"""Telemetry processing pipeline.

Port of the PROGRAM GEOSAT driver in legacy/src/geosat.f.

The legacy driver is a read-decode-convert-screen-propagate-report loop over
standard input. This module keeps that shape but expresses it as a pure
function over an iterable of records, so the same pipeline can be driven by
the CLI, by the HTTP service, and by the characterization tests without
change.
"""
from dataclasses import dataclass, field
from typing import Iterable, List

from . import report as rpt
from .calibration import Alarm, convert, screen
from .frame import CrcFailure, SyncLoss, decode, parse_record
from .orbit import propagate
from .timebase import to_utc


@dataclass
class PassStatistics:
    frames_processed: int = 0
    sync_losses: int = 0
    crc_failures: int = 0
    limit_violations: int = 0


@dataclass
class PassResult:
    lines: List[str] = field(default_factory=list)
    statistics: PassStatistics = field(default_factory=PassStatistics)


def process(records: Iterable[str]) -> PassResult:
    """Run the telemetry processing chain over hex-encoded frame records."""
    result = PassResult()
    stats = result.statistics

    # Mirrors the /FRAME/ common block: FRMCNT persists between frames and is
    # only updated once a frame passes both sync and CRC checks.
    last_frame_count = 0

    for line in records:
        try:
            payload = parse_record(line.rstrip("\n"))
        except ValueError:
            result.lines.append(rpt.MSG_MALFORMED)
            continue

        if payload is None:
            continue

        try:
            frame = decode(payload)
        except SyncLoss:
            stats.sync_losses += 1
            result.lines.append(rpt.MSG_SYNC_LOSS)
            continue
        except CrcFailure:
            stats.crc_failures += 1
            result.lines.append(rpt.crc_failure(last_frame_count))
            continue

        last_frame_count = frame.frame_count
        stats.frames_processed += 1

        eu = convert(frame.raw)
        status = screen(eu)
        stats.limit_violations += sum(1 for s in status if s != Alarm.OK)

        utc = to_utc(frame.gps_seconds)
        ssp = propagate(frame.gps_seconds)

        result.lines.extend(rpt.render_frame(frame, eu, status, utc, ssp))

    result.lines.extend(
        rpt.render_summary(
            stats.frames_processed,
            stats.sync_losses,
            stats.crc_failures,
            stats.limit_violations,
        )
    )

    return result
