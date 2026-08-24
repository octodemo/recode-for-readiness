"""Command-line entry point.

Reads hex-encoded telemetry records on standard input and writes the pass
summary to standard output, exactly as the legacy binary does:

    python -m geosat_modern < ../legacy/tests/golden/pass01.tlm
"""
import sys

from .pipeline import process


def main() -> int:
    result = process(sys.stdin)
    sys.stdout.write("\n".join(result.lines) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
