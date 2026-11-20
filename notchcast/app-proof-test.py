#!/usr/bin/env python3
# script-tests: macos (ditto and codesign)
"""app-proof.py clears both proof domains before each proof and runs every proof under the per-user lock."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("app-proof.py")
# The fake app logs its run and whether the lock was free; `defaults` is a stub that logs, so no real domain is touched.
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
            env = {**os.environ, "HOME": str(scratch / "home"), "LOG": str(log),
                   "PATH": f"{scratch / 'bin'}:{os.environ['PATH']}"}
            result = subprocess.run(["python3", str(SCRIPT), "run", "--app", str(scratch / "Fake.app"),
                                     "hidden-settings", "addon-launcher"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            clear = ["defaults delete app.notchcast.proof", "defaults delete app.notchcast.proof.notchcast", "lock held"]
            self.assertEqual(log.read_text().splitlines(),
                             [*clear, "run hidden-settings", *clear, "run addon-launcher"])


if __name__ == "__main__":
    unittest.main()
