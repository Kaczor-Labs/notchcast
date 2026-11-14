#!/usr/bin/env python3
"""A harness run leaves none of its test preference suites behind, however it ends."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parent.parent
SWEEP = ROOT / "notchcast/pref-sweep.py"
# What run-tests.sh gives the sourced file: `emit_db`, then a run that leaks one suite while it works.
STUB_RUNNER = """#!/bin/bash
set -uo pipefail
emit_db=${EMIT_DB:-0} only="" ran=0
source notchcast/test-harnesses.sh
touch "$NOTCHCAST_PREFS_DIR/tinycast.stub-test.$(uuidgen).plist"
case "${HOW:-pass}" in
    fail) exit 1;;
    term) kill -TERM $$; sleep 5;;
esac
"""


def suite(domain="tinycast.fixture-test"):
    return f"{domain}.{uuid.uuid4()}.plist"


class PrefSweepTest(unittest.TestCase):
    def setUp(self):
        self.scratch = Path(tempfile.mkdtemp(prefix="pref-sweep-"))
        self.addCleanup(shutil.rmtree, self.scratch)
        self.prefs = self.scratch / "prefs"
        self.prefs.mkdir()
        self.env = {**os.environ, "NOTCHCAST_PREFS_DIR": str(self.prefs), "NOTCHCAST_PREF_SWEEP_SETTLE": "0",
                    "NOTCHCAST_PREF_SWEEP_STATE": str(self.scratch / "state")}

    def sweep(self, command, pid):
        subprocess.run(["python3", str(SWEEP), command, str(pid)], env=self.env, check=True)

    def names(self):
        return sorted(path.name for path in self.prefs.iterdir())

    def touch(self, name):
        (self.prefs / name).write_text("x")
        return name

    def run_stub(self, **extra):
        tree = self.scratch / "tree"
        (tree / "notchcast").mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / "notchcast/test-harnesses.sh", tree / "notchcast")
        shutil.copy(SWEEP, tree / "notchcast")
        (tree / "notchcast/harness_inputs.py").write_text("")
        (tree / "runner.sh").write_text(STUB_RUNNER)
        return subprocess.run(["bash", "runner.sh"], cwd=tree, env={**self.env, **extra}).returncode

    def test_only_new_test_suites_are_removed(self):
        old = self.touch(suite("tinycast.hyper-key-test"))
        keep = [old, self.touch("app.notchcast.plist"), self.touch("com.tinycast.app.dev.plist"),
                self.touch("app.notchcast.island.%s.plist" % uuid.uuid4()), self.touch("com.apple.finder.plist"),
                self.touch("notes.plist.tmp-%s" % uuid.uuid4())]
        self.sweep("begin", os.getpid())
        self.touch(suite("tinycast.hyper-key-test"))
        self.touch(suite("app.notchcast.tests"))
        self.touch(f"tinycast.dictation-key-test.{uuid.uuid4()}.dev.plist")
        self.sweep("end", os.getpid())
        self.assertEqual(self.names(), sorted(keep))

    def test_overlapping_runs_leave_the_sweep_to_the_last(self):
        other = subprocess.Popen(["sleep", "30"])
        self.addCleanup(other.kill)
        self.sweep("begin", os.getpid())
        self.sweep("begin", other.pid)
        leak = self.touch(suite())
        self.sweep("end", os.getpid())
        self.assertEqual(self.names(), [leak], "a suite the other run may still use survives")
        self.sweep("end", other.pid)
        self.assertEqual(self.names(), [])

    def test_a_dead_run_does_not_hold_the_sweep(self):
        dead = subprocess.Popen(["true"])
        dead.wait()
        self.sweep("begin", dead.pid)
        self.sweep("begin", os.getpid())
        self.touch(suite())
        self.sweep("end", os.getpid())
        self.assertEqual(self.names(), [])

    def test_nothing_is_removed_without_a_baseline(self):
        keep = self.touch(suite())
        self.sweep("end", os.getpid())
        self.assertEqual(self.names(), [keep])

    def test_a_passing_run_leaves_no_suite(self):
        keep = self.touch(suite())
        self.assertEqual(self.run_stub(), 0)
        self.assertEqual(self.names(), [keep])

    def test_a_failing_run_leaves_no_suite_and_keeps_its_status(self):
        keep = self.touch(suite())
        self.assertEqual(self.run_stub(HOW="fail"), 1)
        self.assertEqual(self.names(), [keep])

    def test_a_terminated_run_leaves_no_suite(self):
        keep = self.touch(suite())
        self.assertEqual(self.run_stub(HOW="term"), 143)
        self.assertEqual(self.names(), [keep])

    def test_an_index_run_sweeps_nothing(self):
        self.assertEqual(self.run_stub(EMIT_DB="1"), 0)
        self.assertEqual(len(self.names()), 1)


if __name__ == "__main__":
    unittest.main()
