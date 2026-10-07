#!/usr/bin/env python3
"""Regression test for remote_audit.sh using a local fake SSH transport."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "remote_audit.sh"


@unittest.skipUnless(sys.platform == "darwin", "remote_audit.sh targets macOS")
class RemoteAuditTest(unittest.TestCase):
    def test_full_run_under_system_bash(self) -> None:
        result, copied_log = self._run(audit_exit=0)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("AUDIT PASSED on test-host", result.stdout)
        self.assertEqual(copied_log, "windows pass\n")

    def test_failed_audit_still_copies_results(self) -> None:
        result, copied_log = self._run(audit_exit=1)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("AUDIT FAILED on test-host (exit 1)", result.stdout)
        self.assertEqual(copied_log, "windows fail\n")

    def test_locked_preflight_fails_when_ssh_masks_exit_status(self) -> None:
        result, copied_log = self._run(audit_exit=0, locked=True)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("screen is locked", result.stdout)
        self.assertIn("preflight failed", result.stdout)
        self.assertEqual(copied_log, "")

    def _run(self, audit_exit: int, locked: bool = False) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory(prefix="parchmatte-remote-test-") as raw:
            temp = Path(raw)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            remote_dir = temp / "remote"
            local_results = temp / "local-results"
            state_marker = temp / "parchmatte-running"
            terminal_close_marker = temp / "terminal-closed"
            self._make_remote_checkout(remote_dir)
            self._make_fake_commands(fake_bin)

            before = set(Path("/tmp").glob("parchmatte-remote.*"))
            env = os.environ.copy()
            env.update(
                {
                    "FAKE_PARCHMATTE_STATE": str(state_marker),
                    "FAKE_TERMINAL_CLOSE": str(terminal_close_marker),
                    "FAKE_AUDIT_EXIT": str(audit_exit),
                    "FAKE_LOCKED": "1" if locked else "0",
                    "PARCHMATTE_LOCAL_RESULTS_DIR": str(local_results),
                    "PARCHMATTE_REMOTE_DIR": str(remote_dir),
                    "PATH": f"{fake_bin}:{env['PATH']}",
                }
            )
            args = ["/bin/bash", str(SCRIPT)]
            if locked:
                args.append("--check")
            else:
                args.extend(["--ref", "e845419f85afc9be2efc1aa41e3cb1a1c72ed61c"])
            args.append("test-host")
            result = subprocess.run(
                args,
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=20,
                check=False,
            )

            self.assertNotIn("syntax error", result.stdout)
            copied = local_results / "parchmatte-test-free" / "windows.log"
            if locked:
                self.assertFalse(copied.exists(), result.stdout)
                copied_log = ""
            else:
                self.assertTrue(copied.exists(), result.stdout)
                copied_log = copied.read_text()
            self.assertFalse(state_marker.exists(), "runner left the app running")
            self.assertEqual(terminal_close_marker.exists(), not locked, "Terminal cleanup mismatch")

            if not locked:
                state_line = next(
                    line for line in result.stdout.splitlines() if "state: test-host:" in line
                )
                state_dir = Path(state_line.split("state: test-host:", 1)[1].strip())
                self.assertFalse(state_dir.exists(), "runner left remote state behind")
            after = set(Path("/tmp").glob("parchmatte-remote.*"))
            self.assertEqual(after, before, "runner left its capture file behind")
            return result, copied_log

    @staticmethod
    def _make_remote_checkout(remote_dir: Path) -> None:
        (remote_dir / "scripts").mkdir(parents=True)
        harness = remote_dir / "Tests" / "Harness"
        harness.mkdir(parents=True)
        build = remote_dir / "scripts" / "build.sh"
        build.write_text(
            "#!/bin/bash\nmkdir -p dist/Parchmatte.app\n",
            encoding="utf-8",
        )
        audit = harness / "run_audit.sh"
        audit.write_text(
            textwrap.dedent(
                """\
                #!/bin/bash
                out="Tests/Harness/results/parchmatte-test-$1"
                mkdir -p "$out"
                rc="${FAKE_AUDIT_EXIT:-0}"
                if [ "$rc" -eq 0 ]; then
                    printf 'windows pass\\n' > "$out/windows.log"
                    printf 'AUDIT PASSED\\n'
                else
                    printf 'windows fail\\n' > "$out/windows.log"
                    printf 'AUDIT FAILED: windows\\n'
                fi
                exit "$rc"
                """
            ),
            encoding="utf-8",
        )
        build.chmod(0o755)
        audit.chmod(0o755)

    @staticmethod
    def _make_fake_commands(fake_bin: Path) -> None:
        dispatcher = fake_bin / "dispatcher"
        dispatcher.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import getpass
                import os
                from pathlib import Path
                import shutil
                import subprocess
                import sys

                name = Path(sys.argv[0]).name
                args = sys.argv[1:]
                marker = Path(os.environ["FAKE_PARCHMATTE_STATE"])

                if name == "ssh":
                    start = args.index("bash")
                    remote_args = args[start + 3:]
                    completed = subprocess.run(
                        ["/bin/bash", "-s", "--", *remote_args],
                        input=sys.stdin.buffer.read(),
                        env=os.environ.copy(),
                    )
                    # Emulate an SSH server that masks remote command failures.
                    raise SystemExit(0)
                if name == "scp":
                    source, destination = args[-2:]
                    source_path = Path(source.split(":", 1)[1])
                    destination_path = Path(destination)
                    destination_path.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(
                        source_path,
                        destination_path / source_path.name,
                        dirs_exist_ok=True,
                    )
                    raise SystemExit(0)
                if name == "git":
                    joined = " ".join(args)
                    if "remote get-url origin" in joined:
                        print("https://example.invalid/parchmatte.git")
                    elif "rev-parse --short HEAD" in joined:
                        print("e845419")
                    elif "log -1 --format=%s" in joined:
                        print("test commit")
                    raise SystemExit(0)
                if name == "pgrep":
                    raise SystemExit(0 if marker.exists() else 1)
                if name == "pkill":
                    marker.unlink(missing_ok=True)
                    raise SystemExit(0)
                if name == "plutil":
                    if "-lint" in args:
                        raise SystemExit(0)
                    if os.environ.get("FAKE_LOCKED") == "1":
                        print("true")
                        raise SystemExit(0)
                    # macOS 15 omits CGSSessionScreenIsLocked when unlocked.
                    raise SystemExit(1)
                if name == "open":
                    if args[:2] == ["-a", "Terminal"]:
                        subprocess.run(
                            ["/bin/bash", args[-1]],
                            env=os.environ.copy(),
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                        raise SystemExit(0)
                    marker.touch()
                    raise SystemExit(0)
                if name == "osascript":
                    if not any("tty of terminalTab" in arg for arg in args):
                        raise SystemExit("Terminal close was not scoped to the audit TTY")
                    Path(os.environ["FAKE_TERMINAL_CLOSE"]).touch()
                    raise SystemExit(0)
                if name == "stat":
                    print(getpass.getuser())
                    raise SystemExit(0)
                if name == "swift":
                    if args == ["--version"]:
                        print("Swift version test")
                    raise SystemExit(0)
                if name == "xcode-select":
                    print("/Library/Developer/CommandLineTools")
                    raise SystemExit(0)
                if name == "sw_vers":
                    print("15.7.4")
                    raise SystemExit(0)
                if name == "uname":
                    print("Darwin")
                    raise SystemExit(0)
                if name in {"caffeinate", "ioreg", "sleep"}:
                    raise SystemExit(0)
                raise SystemExit(f"unexpected fake command: {name}")
                """
            ),
            encoding="utf-8",
        )
        dispatcher.chmod(0o755)
        for name in (
            "caffeinate",
            "git",
            "ioreg",
            "open",
            "osascript",
            "pgrep",
            "pkill",
            "plutil",
            "scp",
            "sleep",
            "ssh",
            "stat",
            "sw_vers",
            "swift",
            "uname",
            "xcode-select",
        ):
            (fake_bin / name).symlink_to(dispatcher)


if __name__ == "__main__":
    unittest.main()
