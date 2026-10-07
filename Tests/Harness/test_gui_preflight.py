#!/usr/bin/env python3
"""Tests for the bounded Terminal permission preflight."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Tests" / "Harness" / "gui_preflight.sh"


class GuiPreflightTest(unittest.TestCase):
    def test_passes_when_both_apple_events_succeed(self) -> None:
        result = self._run(fail="")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("ok    Terminal foreground assist landed", result.stdout)
        self.assertIn("ok    Terminal can drive System Events", result.stdout)
        self.assertIn("ok    Terminal can automate TextEdit", result.stdout)
        self.assertIn("ok    TextEdit can become frontmost", result.stdout)

    def test_reports_each_failed_grant(self) -> None:
        result = self._run(fail="all")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL  Terminal can drive System Events", result.stdout)
        self.assertIn("FAIL  Terminal can automate TextEdit", result.stdout)
        self.assertIn("quit and reopen Terminal", result.stdout)

    def test_reports_when_another_app_keeps_focus(self) -> None:
        result = self._run(fail="", frontmost="System Settings")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL  TextEdit can become frontmost", result.stdout)
        self.assertIn("Close permission prompts", result.stdout)

    def test_uses_functional_checks_when_terminal_assist_fails(self) -> None:
        result = self._run(fail="", activation_fails=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("note  Terminal foreground assist did not land", result.stdout)
        self.assertIn("ok    Terminal can drive System Events", result.stdout)

    def test_reports_locked_console_before_repeating_activation(self) -> None:
        result = self._run(fail="", locked=True)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL  screen is locked", result.stdout)

    @staticmethod
    def _run(
        fail: str,
        frontmost: str = "TextEdit",
        activation_fails: bool = False,
        locked: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix="parchmatte-gui-preflight-") as raw:
            fake = Path(raw) / "osascript"
            fake.write_text(
                "#!/bin/bash\n"
                "if [ \"${FAKE_OSASCRIPT_FAIL:-}\" = all ]; then "
                "echo 'not authorized' >&2; exit 1; fi\n"
                "case \"$*\" in\n"
                "  *'get frontmost of process \"TextEdit\"'*) "
                "printf '%s\\n' \"${FAKE_TEXTEDIT_FRONTMOST:-true}\" ;;\n"
                "  *) printf '%s\\n' \"${FAKE_FRONTMOST:-TextEdit}\" ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            activate = Path(raw) / "activate_app"
            activate.write_text(
                "#!/bin/bash\n"
                "if [ \"${FAKE_LOCKED:-0}\" = 1 ]; then "
                "echo 'activation did not reach the foreground: TextEdit (frontmost: loginwindow)'; exit 1; fi\n"
                "[ \"${FAKE_ACTIVATION_FAILS:-0}\" = 0 ]\n",
                encoding="utf-8",
            )
            activate.chmod(0o755)
            env = os.environ.copy()
            env["FAKE_OSASCRIPT_FAIL"] = fail
            env["FAKE_FRONTMOST"] = frontmost
            env["FAKE_TEXTEDIT_FRONTMOST"] = (
                "true" if frontmost == "TextEdit" else "false"
            )
            env["PARCHMATTE_OSASCRIPT"] = str(fake)
            env["PARCHMATTE_OPEN"] = "/usr/bin/true"
            env["PARCHMATTE_SLEEP"] = "/usr/bin/true"
            env["FAKE_ACTIVATION_FAILS"] = "1" if activation_fails else "0"
            env["FAKE_LOCKED"] = "1" if locked else "0"
            env["PARCHMATTE_ACTIVATE_APP"] = str(activate)
            return subprocess.run(
                ["/bin/bash", str(SCRIPT)],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=5,
                check=False,
            )


if __name__ == "__main__":
    unittest.main()
