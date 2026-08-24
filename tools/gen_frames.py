#!/usr/bin/env python3
"""Generate golden GEOSAT telemetry frames for the characterization suite.

The frame layout and the CRC-16 must match legacy/src/tlmdec.f and
legacy/src/crcchk.f exactly. This generator is deterministic: no clock,
no randomness without a fixed seed, so the golden vectors are stable.
"""
import random
import struct
import sys

SYNC = 0x1ACF
FRMLEN = 32


def crc16(buf):
    """CCITT CRC-16, poly 0x1021, init 0xFFFF, no final xor. Mirrors CRCCHK."""
    crc = 0xFFFF
    for b in buf:
        crc ^= (b << 8) & 0xFFFF
        for _ in range(8):
            msb = crc & 0x8000
            crc = (crc << 1) & 0xFFFF
            if msb:
                crc ^= 0x1021
    return crc & 0xFFFF


def build(scid, apid, frmcnt, gpssec, ch, bad_crc=False, bad_sync=False):
    b = bytearray(FRMLEN)
    sync = 0x0000 if bad_sync else SYNC
    struct.pack_into(">H", b, 0, sync)
    b[2] = scid
    b[3] = apid
    struct.pack_into(">I", b, 4, frmcnt)
    struct.pack_into(">I", b, 8, gpssec)
    struct.pack_into(">H", b, 12, ch["busv"])
    struct.pack_into(">H", b, 14, ch["busi"])
    struct.pack_into(">H", b, 16, ch["batt"])
    struct.pack_into(">h", b, 18, ch["rwrp"])
    struct.pack_into(">h", b, 20, ch["gyrx"])
    struct.pack_into(">h", b, 22, ch["gyry"])
    struct.pack_into(">h", b, 24, ch["gyrz"])
    struct.pack_into(">H", b, 26, ch["pltm"])
    b[28] = ch["xmtp"]
    b[29] = ch["ragc"]
    crc = crc16(b[:30])
    if bad_crc:
        crc ^= 0xFFFF
    struct.pack_into(">H", b, 30, crc)
    return b


def nominal(i):
    """Nominal on-orbit state with slow, deterministic drift."""
    return {
        "busv": 23000 + (i * 7) % 900,        # ~28.1 to 29.2 VDC
        "busi": 26000 + (i * 131) % 4000,     # ~7.9 to 9.2 A
        "batt": 25000 + (i * 53) % 1500,      # ~8 to 12 C
        "rwrp": 2400 + (i * 37) % 600,        # RPM
        "gyrx": 120 - (i * 11) % 240,
        "gyry": -80 + (i * 17) % 160,
        "gyrz": 40 + (i * 5) % 90,
        "pltm": 19000 + (i * 23) % 800,       # ~18 to 20 C
        "xmtp": 200 + (i % 12),
        "ragc": 150 + (i % 20),
    }


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "pass01"
    random.seed(4021)
    out = []
    base_gps = 1_356_998_418   # 2023-01-01-ish, well past the frozen epoch

    if which == "pass01":
        out.append("* GEOSAT PASS 01 -- NOMINAL ON ORBIT, 24 FRAMES")
        for i in range(24):
            f = build(42, 7, 100000 + i, base_gps + i * 4, nominal(i))
            out.append(f.hex().upper())

    elif which == "pass02":
        out.append("* GEOSAT PASS 02 -- ECLIPSE ENTRY, BATTERY AND BUS EXCURSIONS")
        for i in range(16):
            ch = nominal(i)
            if 6 <= i <= 11:
                ch["batt"] = 3000 + i * 200      # cold, drives yellow/red low
                ch["busv"] = 19000 + i * 40      # bus sag
                ch["busi"] = 45000               # high current draw
            f = build(42, 7, 200000 + i, base_gps + 5400 + i * 4, ch)
            out.append(f.hex().upper())

    elif which == "pass03":
        out.append("* GEOSAT PASS 03 -- DEGRADED LINK, SYNC LOSS AND CRC FAILURES")
        for i in range(20):
            ch = nominal(i)
            bs = i in (4, 5, 13)
            bc = i in (8, 9, 17)
            f = build(42, 7, 300000 + i, base_gps + 10800 + i * 4, ch,
                      bad_crc=bc, bad_sync=bs)
            out.append(f.hex().upper())

    elif which == "edge01":
        out.append("* GEOSAT EDGE CASES -- RAIL VALUES, SIGN BOUNDARIES, WRAP")
        cases = [
            dict(nominal(0), busv=0, busi=0, batt=0, rwrp=-32768,
                 gyrx=-32768, gyry=32767, gyrz=0, pltm=0, xmtp=0, ragc=0),
            dict(nominal(0), busv=65535, busi=65535, batt=65535, rwrp=32767,
                 gyrx=32767, gyry=-32768, gyrz=-1, pltm=65535, xmtp=255,
                 ragc=255),
            dict(nominal(0), rwrp=-1, gyrx=-1, gyry=-1, gyrz=-1),
            dict(nominal(0), pltm=0x000F),   # exercises the CH11 nibble coupling
            dict(nominal(0), pltm=0xFF0F),
        ]
        for i, ch in enumerate(cases):
            f = build(42, 7, 900000 + i, base_gps + i, ch)
            out.append(f.hex().upper())

    else:
        sys.exit("unknown vector: %s" % which)

    print("\n".join(out))


if __name__ == "__main__":
    main()
