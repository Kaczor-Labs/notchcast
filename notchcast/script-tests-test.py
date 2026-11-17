#!/usr/bin/env python3
"""Verify script-test discovery, interpreter dispatch, isolation and diff selection."""
from contextlib import chdir, redirect_stderr, redirect_stdout
import io
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("script-tests.py").resolve()
DEFAULT = ["notchcast/nested/plain-test.py", "notchcast/plain-test.sh", "notchcast/land-test.sh",
           "notchcast/generated-retry-test.mjs", "notchcast/gallery/check-pixels-test.swift",
           "notchcast/install-app-test.sh"]
# Who names whom: land-test reaches hold.sh only through land.sh; plain-test reaches a doc it names.
SOURCES = {
    "notchcast/land-test.sh": 'bash "$root/notchcast/land.sh"\n',
    "notchcast/land.sh": "source hold.sh\n",
    "notchcast/hold.sh": "",
    "notchcast/plain-test.sh": "grep -q x notchcast/docs/guide.md\n",
    "notchcast/docs/guide.md": "see land.sh\n",
    "notchcast/install-app-test.sh": "python3 notchcast/vendor/Engine/build.py\n",
    "notchcast/vendor/Engine/build.py": "import land_sh  # land.sh\n",
    "notchcast/script-tests.py": "",
}


class ScriptTestsTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="script-tests-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        for name in DEFAULT + list(SOURCES):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(SOURCES.get(name, ""))

    def invoke(self, arguments, returncode=0, changed="", stdout=b"log line\n"):
        output = io.StringIO()
        self.stderr = io.StringIO()

        def git(command, **_):
            if command[1] == "ls-files":
                return "\n".join(DEFAULT + list(SOURCES)) + "\n"
            if changed is None:
                raise subprocess.CalledProcessError(128, command)
            return changed

        with chdir(self.root), patch.object(sys, "argv", [str(SCRIPT), *arguments]), \
                redirect_stdout(output), redirect_stderr(self.stderr), patch("subprocess.run") as run, \
                patch("subprocess.check_output", side_effect=git):
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

    def test_base_selects_tests_whose_inputs_changed_through_any_depth(self):
        status, output, _ = self.invoke(["--base", "base", "--list"], changed="notchcast/hold.sh\n")
        self.assertEqual(0, status)
        self.assertEqual(["notchcast/land-test.sh"], output.splitlines())

    def test_a_named_doc_is_an_input_but_names_nothing(self):
        _, output, _ = self.invoke(["--base", "base", "--list"], changed="notchcast/docs/guide.md\n")
        self.assertEqual(["notchcast/plain-test.sh"], output.splitlines())
        _, output, _ = self.invoke(["--base", "base", "--list"], changed="notchcast/vendor/Engine/build.py\n")
        self.assertEqual(["notchcast/install-app-test.sh"], output.splitlines())

    def test_a_diff_outside_every_input_runs_nothing(self):
        status, output, commands = self.invoke(["--base", "base"], changed="Tinycast/App/AppCore.swift\n")
        self.assertEqual(0, status)
        self.assertEqual([], commands)
        self.assertIn("reaches none of their inputs", output)

    def test_a_changed_test_selects_itself(self):
        _, output, _ = self.invoke(["--base", "base", "--list"], changed="notchcast/nested/plain-test.py\n")
        self.assertEqual(["notchcast/nested/plain-test.py"], output.splitlines())

    def test_an_unreadable_diff_or_a_changed_runner_runs_everything(self):
        _, output, _ = self.invoke(["--base", "base", "--list"], changed=None)
        self.assertEqual(sorted(DEFAULT), output.splitlines())
        self.assertIn("running every test", self.stderr.getvalue())
        _, output, _ = self.invoke(["--base", "base", "--list"], changed="notchcast/script-tests.py\n")
        self.assertEqual(sorted(DEFAULT), output.splitlines())


if __name__ == "__main__":
    unittest.main(verbosity=2)
