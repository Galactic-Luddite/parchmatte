#!/usr/bin/env python3
"""The audit verdict must include the preference restoration result."""

from pathlib import Path
import subprocess
import unittest


FINISH = Path(__file__).with_name("audit_finish.sh")


class AuditFinishTest(unittest.TestCase):
    def test_restore_failure_overrides_suites_pass(self) -> None:
        result = self._run(0, 1)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("AUDIT PASSED", result.stdout)

    def test_success_requires_suites_and_restore(self) -> None:
        result = self._run(0, 0)
        self.assertEqual(result.returncode, 0)
        self.assertIn("AUDIT PASSED", result.stdout)

    def test_suite_failure_is_preserved_after_restore(self) -> None:
        result = self._run(2, 0)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("AUDIT PASSED", result.stdout)

    @staticmethod
    def _run(suite_exit: int, restore_exit: int) -> subprocess.CompletedProcess[str]:
        script = (
            f'source "{FINISH}"\n'
            f'restore_prefs() {{ return {restore_exit}; }}\n'
            'trap audit_finish EXIT\n'
            f'exit {suite_exit}\n'
        )
        return subprocess.run(
            ["/bin/bash", "-c", script], capture_output=True, text=True, check=False
        )


if __name__ == "__main__":
    unittest.main()
