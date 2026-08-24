"""Engineering-unit conversion and limit screening.

Port of ENGCNV and LIMCHK in legacy/src/geosat.f.

Coefficients are the flight calibration set from the 1986 thermal-vacuum
campaign (cal report TV-86-09). Channel 3 uses the revised thermistor fit
from ECO 91-217; the original linear fit read 4 degC high at the cold end
and produced spurious red alarms during eclipse.

Limits are the on-orbit set from flight operations handbook FOH-4021 rev C,
table 5-3. Channels with no meaningful limits (9 and 11) are given wide-open
values rather than being special-cased, because the original display driver
indexed this table directly and faulted on a short table.
"""
from enum import IntEnum
from typing import List

from .precision import f32

CHANNEL_COUNT = 11

CHANNEL_NAMES = [
    "BUSV", "BUSI", "BATT", "RWRP", "GYRX", "GYRY",
    "GYRZ", "PLTM", "XMTP", "RAGC", "SAAN",
]

CHANNEL_UNITS = [
    "VDC", "AMPS", "DEG C", "RPM", "DEG/S", "DEG/S",
    "DEG/S", "DEG C", "WATTS", "DBM", "DEG",
]

# EU = C0 + C1*raw + C2*raw*raw
C0 = [0.0, 0.0, -55.0, 0.0, 0.0, 0.0, 0.0, -40.0, 0.0, -120.0, 0.0]
C1 = [
    0.0012207, 0.0003052, 0.0025400, 0.5000000,
    0.0019531, 0.0019531, 0.0019531, 0.0030518,
    0.0392157, 0.4705882, 1.0000000,
]
C2 = [0.0, 0.0, -1.2e-8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

RED_LOW = [24.0, 0.0, -20.0, -6000.0, -8.0, -8.0, -8.0, -30.0, 0.0, -95.0, 0.0]
YEL_LOW = [26.0, 0.5, -10.0, -5000.0, -5.0, -5.0, -5.0, -20.0, 1.0, -90.0, 0.0]
YEL_HIGH = [32.5, 14.0, 35.0, 5000.0, 5.0, 5.0, 5.0, 45.0, 9.0, -55.0, 360.0]
RED_HIGH = [34.0, 16.0, 45.0, 6000.0, 8.0, 8.0, 8.0, 55.0, 10.0, -45.0, 360.0]


class Alarm(IntEnum):
    OK = 0
    YELLOW_LOW = 1
    YELLOW_HIGH = 2
    RED_LOW = 3
    RED_HIGH = 4


ALARM_TEXT = {
    Alarm.OK: " OK",
    Alarm.YELLOW_LOW: " YL",
    Alarm.YELLOW_HIGH: " YH",
    Alarm.RED_LOW: " RL",
    Alarm.RED_HIGH: " RH",
}


def convert(raw: List[int]) -> List[float]:
    """Apply the per-channel calibration polynomial in single precision."""
    eu = []
    for i in range(CHANNEL_COUNT):
        r = f32(float(raw[i]))
        term1 = f32(f32(C1[i]) * r)
        term2 = f32(f32(f32(C2[i]) * r) * r)
        value = f32(f32(f32(C0[i]) + term1) + term2)
        eu.append(value)

    # Solar array angle is already in degrees and wraps at 360.
    if eu[10] >= 360.0:
        eu[10] = f32(eu[10] - 360.0)

    return eu


def screen(eu: List[float]) -> List[Alarm]:
    """Screen engineering values against the on-orbit limit set."""
    status = []
    for i in range(CHANNEL_COUNT):
        v = eu[i]
        if v < RED_LOW[i]:
            status.append(Alarm.RED_LOW)
        elif v > RED_HIGH[i]:
            status.append(Alarm.RED_HIGH)
        elif v < YEL_LOW[i]:
            status.append(Alarm.YELLOW_LOW)
        elif v > YEL_HIGH[i]:
            status.append(Alarm.YELLOW_HIGH)
        else:
            status.append(Alarm.OK)
    return status
