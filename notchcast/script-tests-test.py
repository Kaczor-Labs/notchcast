#!/usr/bin/env python3
"""Verify script-test lanes, recursive discovery, interpreter dispatch and isolation."""
from contextlib import chdir, redirect_stderr, redirect_stdout
import io
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("script-tests.py").resolve()
DEFAULT = ["notchcast/nested/plain-test.py", "notchcast/plain-test.sh", "notchcast/land-test.sh",
           "notchcast/generated-retry-test.mjs", "notchcast/gallery/check-pixels-test.swift",
           "notchcast/install-app-test.sh"]


class ScriptTestsTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="script-tests-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        for name in DEFAULT + ["notchcast/helper.py"]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()

    def invoke(self, arguments, returncode=0, changed="notchcast/land.sh\n", stdout=b"log line\n"):
        output = io.StringIO()
        self.stderr = io.StringIO()
        with chdir(self.root), patch.object(sys, "argv", [str(SCRIPT), *arguments]), \
                redirect_stdout(output), redirect_stderr(self.stderr), patch("subprocess.run") as run, \
                patch("subprocess.check_output", return_value=changed):
            run.return_value.returncode = returncode
            run.return_value.stdout = stdout
            try:
                runpy.run_path(str(SCRIPT), run_name="__main__")
                status = 0
            except SystemExit as error:
                status = error.code
        self.calls = run.call_args_list
        return status, output.getvalue(), [call.args[0] for call in run.call_args_list]

    def test_default_discovers_four_runtimes(self):
        status, output, commands = self.invoke(["--list"])
        self.assertEqual(0, status)
        self.assertEqual(sorted(DEFAULT), output.splitlines())
        self.assertEqual([], commands)

    def test_execution_uses_each_interpreter(self):
        status, output, commands = self.invoke([])
        self.assertEqual(0, status)
        self.assertIn("6 passed, 0 failed", output)
        self.assertEqual(sorted([
            ["python3", DEFAULT[0]], ["bash", DEFAULT[1]], ["bash", DEFAULT[2]], ["node", DEFAULT[3]],
            ["swift", "-swift-version", "6", DEFAULT[4]], ["bash", DEFAULT[5]],
        ]), sorted(commands))

    def test_each_test_has_its_own_tmpdir_and_whole_output(self):
        status, output, _ = self.invoke([], stdout=b"first\nsecond\n")
        self.assertEqual(0, status)
        tmpdirs = {call.kwargs["env"]["TMPDIR"] for call in self.calls}
        self.assertEqual(6, len(tmpdirs))
        for path in DEFAULT:
            self.assertRegex(output, rf"=== {path} ok [\d.]+s ===\nfirst\nsecond\n")

    def test_test_failure_fails_the_lane(self):
        status, output, commands = self.invoke([], returncode=1)
        self.assertNotEqual(0, status)
        self.assertEqual(6, len(commands))
        self.assertIn("0 passed, 6 failed", output)
        self.assertEqual(sorted(DEFAULT), self.stderr.getvalue().splitlines())

    def test_all_lists_every_test(self):
        status, output, commands = self.invoke(["--all", "--list"])
        self.assertEqual(0, status)
        self.assertEqual(sorted(DEFAULT), output.splitlines())
        self.assertEqual([], commands)

    def test_land_test_runs_only_when_its_inputs_change(self):
        status, output, _ = self.invoke(["--list"], changed="")
        self.assertEqual(0, status)
        self.assertEqual(sorted(set(DEFAULT) - {"notchcast/land-test.sh"}), output.splitlines())
        self.assertIn("Skipping notchcast/land-test.sh", self.stderr.getvalue())
        status, output, _ = self.invoke(["--all", "--list"], changed="")
        self.assertIn("notchcast/land-test.sh", output.splitlines())

    def test_runner_splits_on_the_macos_line(self):
        (self.root / "notchcast/land-test.sh").write_text("#!/bin/bash\n# script-tests: macos (lockf)\n")
        (self.root / "notchcast/generated-retry-test.mjs").write_text("// script-tests: macos (xcrun)\n")
        (self.root / "notchcast/plain-test.sh").write_text("echo '# script-tests: macos'\n")
        macos = ["notchcast/generated-retry-test.mjs", "notchcast/land-test.sh"]
        _, output, _ = self.invoke(["--all", "--list", "--runner", "macos"])
        self.assertEqual(macos, output.splitlines())
        _, output, _ = self.invoke(["--all", "--list", "--runner", "linux"])
        self.assertEqual(sorted(set(DEFAULT) - set(macos)), output.splitlines())


if __name__ == "__main__":
    unittest.main(verbosity=2)

