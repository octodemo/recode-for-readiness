"""Quick-look subsatellite point.

Port of ORBPRP in legacy/src/geosat.f.

This is the quick-look propagator only. It assumes a circular orbit at the
nominal mission altitude and ignores J2, drag, and all maneuver history. The
precision ephemeris is produced by the FDF and delivered separately. Per memo
GS-89-112 this routine must not be used for any pointing or conjunction
product.

Elements are frozen at the epoch below because the element loader was never
ported off the VAX.

Every arithmetic step below is rounded to binary32 individually, in the same
left-to-right association the FORTRAN expressions use. Rounding only at the
end of an expression is not equivalent: it produces a double-rounded result
that diverges from the original once the operands are large.

KNOWN DEFECT -- PRESERVED DELIBERATELY
--------------------------------------
`dt` is computed and carried in single precision. For current epochs it is
on the order of 7.3e8 seconds, which exceeds the ~7 significant decimal
digits binary32 provides. The low bits of the time delta are therefore
discarded, and the propagated subsatellite point does not change between
telemetry frames four seconds apart.

This port reproduces that behaviour exactly, because the characterization
suite pins current output. It is recorded as a finding for the modernization
backlog rather than silently corrected: changing it changes every SSP value
the archive has ever recorded, and that is a mission-assurance decision, not
a refactoring decision.
"""
import math
from dataclasses import dataclass

from .precision import f32

PI = f32(3.14159265)
TWO_PI = f32(2.0 * PI)
EARTH_RADIUS_KM = f32(6378.137)
MU = f32(398600.4418)

ELEMENT_ALTITUDE_KM = f32(785.0)
ELEMENT_INCLINATION_DEG = f32(98.6)
ELEMENT_RAAN_DEG = f32(142.35)
ELEMENT_EPOCH_GPS = 630720000

EARTH_ROTATION_DEG_PER_DAY = f32(360.985647)

_DEG = f32(180.0)
_FULL_TURN = f32(360.0)
_SECONDS_PER_DAY = f32(86400.0)


@dataclass(frozen=True)
class SubsatellitePoint:
    latitude_deg: float
    longitude_deg: float
    altitude_km: float


def _mul(a, b):
    return f32(a * b)


def _div(a, b):
    return f32(a / b)


def _add(a, b):
    return f32(a + b)


def _sub(a, b):
    return f32(a - b)


def _rad(degrees):
    """degrees * PI / 180.0, associating left to right as FORTRAN does."""
    return _div(_mul(degrees, PI), _DEG)


def _deg(radians):
    """radians * 180.0 / PI, associating left to right as FORTRAN does."""
    return _div(_mul(radians, _DEG), PI)


def propagate(gps_seconds: int) -> SubsatellitePoint:
    """Propagate the quick-look subsatellite point for a GPS timestamp."""
    a = _add(EARTH_RADIUS_KM, ELEMENT_ALTITUDE_KM)

    # PERIOD = 2.0 * PI * SQRT((A * A * A) / MU)
    a_cubed = _mul(_mul(a, a), a)
    period = _mul(TWO_PI, f32(math.sqrt(_div(a_cubed, MU))))

    # Single precision, deliberately. See module docstring.
    dt = f32(float(gps_seconds - ELEMENT_EPOCH_GPS))

    # U = 2.0 * PI * (DT / PERIOD);  ARGLAT = AMOD(U, 2.0 * PI)
    u = _mul(TWO_PI, _div(dt, period))
    arg_lat = f32(math.fmod(u, TWO_PI))

    inc_rad = _rad(ELEMENT_INCLINATION_DEG)
    sin_i = f32(math.sin(inc_rad))

    # XLAT = ASIN(SINI * SIN(ARGLAT)) * 180.0 / PI
    latitude = _deg(f32(math.asin(_mul(sin_i, f32(math.sin(arg_lat))))))

    # RATE = 360.985647 / 86400.0;  LONASC = ELRAAN - RATE * DT
    rate = _div(EARTH_ROTATION_DEG_PER_DAY, _SECONDS_PER_DAY)
    lon_ascending = _sub(ELEMENT_RAAN_DEG, _mul(rate, dt))

    # XLON = LONASC + ATAN2(COS(ELINC)*SIN(ARGLAT), COS(ARGLAT)) * 180.0 / PI
    in_track = _deg(
        f32(
            math.atan2(
                _mul(f32(math.cos(inc_rad)), f32(math.sin(arg_lat))),
                f32(math.cos(arg_lat)),
            )
        )
    )

    longitude = _add(lon_ascending, in_track)
    longitude = f32(math.fmod(longitude, _FULL_TURN))
    if longitude > 180.0:
        longitude = _sub(longitude, _FULL_TURN)
    if longitude < -180.0:
        longitude = _add(longitude, _FULL_TURN)

    return SubsatellitePoint(
        latitude_deg=latitude,
        longitude_deg=longitude,
        altitude_km=ELEMENT_ALTITUDE_KM,
    )
