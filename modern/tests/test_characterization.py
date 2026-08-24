"""Characterization tests: modern port versus the compiled legacy binary.

These are not unit tests. They assert one thing only -- that for every golden
telemetry vector, the modernized pipeline emits output that is byte-for-byte
identical to what the 1987 FORTRAN deck emits on the same input.

That is the mission-assurance property. The archive loader parses this output
by fixed column position, so "equivalent" is not good enough; it has to be
identical.

The legacy binary is built on demand. If gfortran is unavailable the parity
tests are skipped rather than silently passing -- a characterization test
that cannot execute the reference implementation proves nothing.

Run:  python -m unittest discover -s modern/tests -t .
"""
import pathlib
import shutil
import subprocess
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
LEGACY = REPO / "legacy"
LEGACY_BIN = LEGACY / "build" / "geosat"
GOLDEN = LEGACY / "tests" / "golden"
MODERN = REPO / "modern"

VECTORS = ["pass01", "pass02", "pass03", "edge01"]


def _build_legacy() -> bool:
    if not shutil.which("gfortran"):
        return False
    result = subprocess.run(
        ["make", "--silent"], cwd=LEGACY, capture_output=True, text=True
    )
    return result.returncode == 0 and LEGACY_BIN.exists()


class CharacterizationTest(unittest.TestCase):
    """Byte-for-byte parity against the reference implementation."""

    legacy_available = False

    @classmethod
    def setUpClass(cls):
        cls.legacy_available = _build_legacy()

    def _run_legacy(self, vector: str) -> str:
        with open(GOLDEN / ("%s.tlm" % vector), "rb") as handle:
            result = subprocess.run(
                [str(LEGACY_BIN)], stdin=handle, capture_output=True
            )
        self.assertEqual(result.returncode, 0, "legacy binary failed on %s" % vector)
        return result.stdout.decode()

    def _run_modern(self, vector: str) -> str:
        with open(GOLDEN / ("%s.tlm" % vector), "rb") as handle:
            result = subprocess.run(
                ["python3", "-m", "geosat_modern"],
                stdin=handle,
                capture_output=True,
                cwd=MODERN,
            )
        self.assertEqual(
            result.returncode, 0, "modern pipeline failed on %s: %s"
            % (vector, result.stderr.decode())
        )
        return result.stdout.decode()

    def test_parity(self):
        if not self.legacy_available:
            self.skipTest("gfortran unavailable; cannot build the reference binary")

        for vector in VECTORS:
            with self.subTest(vector=vector):
                expected = self._run_legacy(vector)
                actual = self._run_modern(vector)
                if expected != actual:
                    exp_lines = expected.splitlines()
                    act_lines = actual.splitlines()
                    detail = []
                    for index in range(max(len(exp_lines), len(act_lines))):
                        left = exp_lines[index] if index < len(exp_lines) else "<eof>"
                        right = act_lines[index] if index < len(act_lines) else "<eof>"
                        if left != right:
                            detail.append(
                                "line %d\n  legacy: %r\n  modern: %r"
                                % (index + 1, left, right)
                            )
                        if len(detail) >= 5:
                            break
                    self.fail(
                        "output diverged from the legacy binary on %s\n%s"
                        % (vector, "\n".join(detail))
                    )

    def test_expected_files_match_binary(self):
        """The checked-in expected/ files must still reflect the real binary."""
        if not self.legacy_available:
            self.skipTest("gfortran unavailable; cannot build the reference binary")

        for vector in VECTORS:
            with self.subTest(vector=vector):
                recorded = (LEGACY / "tests" / "expected" / ("%s.out" % vector)).read_text()
                self.assertEqual(
                    recorded,
                    self._run_legacy(vector),
                    "checked-in golden output for %s is stale" % vector,
                )


if __name__ == "__main__":
    unittest.main()
