import os
import platform
import subprocess
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(platform.system() == "Darwin", "AppKit requires macOS")
class TapCounterTests(unittest.TestCase):
    def test_persistence_events_months_and_rendering(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "counter-tests"
            sources = [root / "Sources/TapCounterAppearance.swift", root / "Sources/WalletTapCounter.swift",
                       root / "Sources/TapCounterRenderer.swift", root / "tests/test_tap_counters.swift"]
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources), "-o", str(binary)],
                                      capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, env=os.environ)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(result.stdout.count("PASS:"), 6)


if __name__ == "__main__":
    unittest.main()
