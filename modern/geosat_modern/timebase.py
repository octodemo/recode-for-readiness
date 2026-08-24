"""GPS-to-UTC time conversion.

Port of TIMCNV in legacy/src/geosat.f.

The GPS epoch is 1980-01-06 00:00:00 UTC. The leap-second offset is a
hand-maintained constant in the legacy source, last updated 2016-12-31.
It is reproduced here as a constant rather than sourced from a leap-second
table on purpose: changing it would change the output, and the point of this
port is to not change the output.

Recorded for the modernization backlog, not fixed here:
LEAP_SECONDS is stale for any epoch after 2016-12-31. Replacing it with a
maintained table is a behavioural change and must be its own reviewed change
with its own updated golden vectors.
"""
from dataclasses import dataclass

GPS_EPOCH_YEAR = 1980
LEAP_SECONDS = 18
MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


@dataclass(frozen=True)
class UtcTime:
    year: int
    month: int
    day: int
    hour: int
    minute: int
    second: int
    day_of_year: int


def _is_leap(year: int) -> bool:
    if year % 400 == 0:
        return True
    if year % 100 == 0:
        return False
    return year % 4 == 0


def to_utc(gps_seconds: int) -> UtcTime:
    """Convert GPS seconds of epoch to UTC calendar fields."""
    total = gps_seconds - LEAP_SECONDS

    days, remainder = divmod(total, 86400)

    hour, rem = divmod(remainder, 3600)
    minute, second = divmod(rem, 60)

    # Walk forward from the GPS epoch, 1980-01-06.
    year = GPS_EPOCH_YEAR
    days += 5

    while True:
        length = 366 if _is_leap(year) else 365
        if days < length:
            break
        days -= length
        year += 1

    day_of_year = days + 1

    month = 1
    while True:
        length = MONTH_DAYS[month - 1]
        if month == 2 and _is_leap(year):
            length = 29
        if days < length:
            break
        days -= length
        month += 1

    return UtcTime(
        year=year,
        month=month,
        day=days + 1,
        hour=hour,
        minute=minute,
        second=second,
        day_of_year=day_of_year,
    )
