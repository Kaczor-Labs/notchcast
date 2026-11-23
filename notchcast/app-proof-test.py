#!/usr/bin/env python3
# script-tests: macos (ditto and codesign)
"""app-proof.py clears both proof domains before each proof and runs every proof under the per-user lock."""
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("app-proof.py")
SPEC = importlib.util.spec_from_file_location("app_proof", SCRIPT)
proof = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(proof)
CI = {"GITHUB_ACTIONS": "true", "GITHUB_JOB": "proof", "RUNNER_ENVIRONMENT": "github-hosted"}
# The fake app logs its run and whether the lock was free; a `defaults` stub touches no domain.
APP = """#!/usr/bin/env python3
import fcntl, os
with open(os.environ["LOG"], "a") as log:
    with open(os.path.expanduser("~/Library/Caches/app.notchcast.proof.lock"), "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            log.write("lock free\\n")
        except BlockingIOError:
            log.write("lock held\\n")
    log.write("run " + os.environ["NOTCHCAST_PROOF"] + "\\n")
print("PROOF PASS " + os.environ["NOTCHCAST_PROOF"])
"""


class AppProofTests(unittest.TestCase):
    def test_run_refuses_a_host_before_starting_work(self):
        for env in ({}, {"CI": "true", "NOTCHCAST_ISOLATED_RUNNER": "1"},
                    {**CI, "GITHUB_JOB": "mac"}, {**CI, "RUNNER_ENVIRONMENT": "self-hosted"}):
            with self.subTest(env=env), patch.dict(os.environ, env, clear=True), \
                    patch.object(sys, "argv", [str(SCRIPT), "run", "addon-off"]), \
                    patch.object(proof, "command", return_value=subprocess.CompletedProcess([], 0, stdout="0\n")) as command:
                with self.assertRaisesRegex(SystemExit, r"^App proof runs only in a guest or CI\.$"):
                    proof.main()
                command.assert_called_once_with(["/usr/sbin/sysctl", "-n", "kern.hv_vmm_present"], capture_output=True, text=True)

    def test_hosted_proof_job_is_allowed(self):
        with patch.dict(os.environ, CI, clear=True), patch.object(proof, "command") as command:
            self.assertTrue(proof.can_run_proof())
            command.assert_not_called()

    def test_guest_signal_is_allowed(self):
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(proof, "command", return_value=subprocess.CompletedProcess([], 0, stdout="1\n")):
            self.assertTrue(proof.can_run_proof())

    def test_unavailable_guest_signal_fails_closed(self):
        for error in (FileNotFoundError(), subprocess.CalledProcessError(1, "sysctl")):
            with self.subTest(error=error), patch.dict(os.environ, {}, clear=True), \
                    patch.object(proof, "command", side_effect=error):
                self.assertFalse(proof.can_run_proof())

    def test_each_proof_starts_from_cleared_domains_under_the_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            app = scratch / "Fake.app/Contents"
            (app / "MacOS").mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "fake", "CFBundleExecutable": "fake"}))
            (app / "MacOS/fake").write_text(APP)
            (app / "MacOS/fake").chmod(0o755)
            (scratch / "bin").mkdir()
            (scratch / "bin/defaults").write_text('#!/bin/bash\necho "defaults $*" >> "$LOG"\nexit 1\n')
            (scratch / "bin/defaults").chmod(0o755)
            log = scratch / "log"
            env = {**os.environ, **CI, "HOME": str(scratch / "home"), "LOG": str(log),
                   "PATH": f"{scratch / 'bin'}:{os.environ['PATH']}"}
            result = subprocess.run(["python3", str(SCRIPT), "run", "--app", str(scratch / "Fake.app"),
                                     "hidden-settings", "addon-launcher"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            clear = ["defaults delete app.notchcast.proof", "defaults delete app.notchcast.proof.notchcast", "lock held"]
            self.assertEqual(log.read_text().splitlines(),
                             [*clear, "run hidden-settings", *clear, "run addon-launcher"])


if __name__ == "__main__":
    unittest.main()
