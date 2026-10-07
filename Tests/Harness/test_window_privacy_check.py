import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "scripts" / "check_window_privacy.py"


class WindowPrivacyCheckTests(unittest.TestCase):
    def run_check(self, source: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "fixture.c"
            fixture.write_text(source, encoding="utf-8")
            return subprocess.run(
                ["python3", str(CHECK), str(fixture)],
                text=True,
                capture_output=True,
                check=False,
            )

    def test_accepts_public_query_option(self):
        result = self.run_check("CGWindowListCreate(kCGWindowListOptionOnScreenAboveWindow, 1);")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_window_title_key(self):
        result = self.run_check("entry[kCGWindowName];")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("kCGWindowName", result.stdout)

    def test_rejects_other_undocumented_metadata_key(self):
        result = self.run_check("entry[kCGWindowAlpha];")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("kCGWindowAlpha", result.stdout)


if __name__ == "__main__":
    unittest.main()
