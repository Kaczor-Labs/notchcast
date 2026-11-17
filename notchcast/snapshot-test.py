#!/usr/bin/env python3
"""Snapshot planning and manual-run failure checks."""
import contextlib
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import os
import re
import subprocess
from pathlib import Path
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from ci import release_tags, version_key

source = os.environ.get("SNAPSHOT_MODULE", str(Path(__file__).with_name("snapshot.py")))
spec = importlib.util.spec_from_loader("snapshot", SourceFileLoader("snapshot", source))
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


class SnapshotTests(unittest.TestCase):
    def test_workflow_lets_a_push_supersede_and_gates_publish(self):
        root = Path(__file__).resolve().parent.parent
        revision = os.environ.get("SNAPSHOT_WORKFLOW_REF")
        workflow = (subprocess.check_output(
            ["git", "show", f"{revision}:.github/workflows/snapshot.yml"], cwd=root, text=True)
            if revision else (root / ".github/workflows/snapshot.yml").read_text())
        header, jobs = workflow.split("\njobs:\n", 1)
        self.assertEqual(len(re.findall(r"^\s*concurrency:", workflow, re.M)), 1)
        self.assertIn("\nconcurrency:\n  group: snapshot\n"
                      "  cancel-in-progress: ${{ github.event_name == 'push' }}\n", header + "\n")
        self.assertNotRegex(jobs, r"(?m)^\s+concurrency:")
        sections = dict(re.findall(r"^  (\w+):\n(.*?)(?=^  \w+:\n|\Z)", jobs, re.M | re.S))
        self.assertNotIn("check", sections)
        self.assertLess(sections["plan"].index("run: python3 notchcast/snapshot-test.py"),
                        sections["plan"].index("run: python3 notchcast/snapshot.py"))
        self.assertIn("    runs-on: ubuntu-latest\n", sections["plan"])
        self.assertIn("    runs-on: ubuntu-latest\n", sections["gate"])
        self.assertIn("run: python3 notchcast/snapshot.py wait", sections["gate"])
        self.assertIn("    needs: [snapshot, gate]\n", sections["publish"])
        checked = sections["publish"].index("run: python3 notchcast/snapshot.py check")
        self.assertLess(checked, sections["publish"].index("actions/deploy-key"))
        self.assertLess(checked, sections["publish"].index("run: notchcast/publish-snapshot.sh"))
        self.assertIn('cron: "7,27,47 * * * *"', header)
        self.assertNotIn("snapshot-test.py", (root / "notchcast/ci-tests.sh").read_text())

    def test_mirror_parser(self):
        self.assertIsNone(version_key("v0.12.7-beta.131.snapshot.20261104090000"))
        self.assertLess(version_key("v0.12.7-beta.131"), version_key("v0.12.8-beta.1"))

    def test_mirrors_survive_snapshot_pages(self):
        pages = [[dict(tag_name=f"v0.12.7.snapshot.{n}") for n in range(100)],
                 [dict(tag_name="v0.12.7-beta.131")]]
        with patch("ci.run", return_value=json.dumps(pages)) as run:
            self.assertIn("v0.12.7-beta.131", release_tags("owner/repo"))
        run.assert_called_once_with("gh", "api", "--paginate", "--slurp",
                                    "repos/owner/repo/releases?per_page=100")

    def test_first_snapshot_and_failed_attempt_do_not_block(self):
        result = snapshot.plan(self.releases[:1], "current-main", lambda tag: "old",
                               datetime(2026, 11, 5, 12, tzinfo=timezone.utc), "workflow_dispatch")
        self.assertEqual(result, {"tag": "v1.0.0.snapshot.20261105120000"})

    def test_publication_time_does_not_extend_gate(self):
        self.assertEqual(self.plan(minute=50), self.plan(minute=49))

    releases = [{"tagName": "v1.0.0", "isDraft": False},
                {"tagName": "v1.0.0.snapshot.20261105120000", "isDraft": False}]

    def plan(self, event="push", minute=30, commit="old", skip_gate=False):
        return snapshot.plan(self.releases, "current-main", lambda tag: commit,
                             datetime(2026, 11, 5, 12, minute, tzinfo=timezone.utc), event, skip_gate)

    def test_dispatch_gate_names_sha_and_open_time(self):
        result = self.plan("workflow_dispatch")
        self.assertIn("current-main", result["closed"])
        self.assertIn("2026-11-05 12:50:00 UTC", result["closed"])

    def test_skip_gate_only_bypasses_timer(self):
        self.assertIn("tag", self.plan("workflow_dispatch", skip_gate=True))
        self.assertEqual(self.plan("workflow_dispatch", commit="current-main", skip_gate=True),
                         {"error": "unchanged main current-main"})

    def test_dispatch_unchanged_is_error(self):
        self.assertEqual(self.plan("workflow_dispatch", commit="current-main"),
                         {"error": "unchanged main current-main"})

    def test_closed_gate_plans_its_opening_time(self):
        self.assertEqual(self.plan(), {"tag": "v1.0.0.snapshot.20261105125000"})
        self.assertEqual(self.plan("schedule"), {"tag": "v1.0.0.snapshot.20261105125000"})

    def test_gate_open_plans_tag(self):
        self.assertEqual(self.plan(minute=50), {"tag": "v1.0.0.snapshot.20261105125000"})

    def test_gate_open_plans_now(self):
        self.assertEqual(self.plan(minute=55), {"tag": "v1.0.0.snapshot.20261105125500"})

    def test_automatic_unchanged_skips(self):
        self.assertEqual(self.plan(commit="current-main"), {"skip": "unchanged main current-main"})

    def stale(self, current="current-main", minute=50, tag="v1.0.0.snapshot.20261105125000",
              releases=None, skip_gate=False):
        return snapshot.stale(releases or self.releases, tag, "current-main", current,
                              datetime(2026, 11, 5, 12, minute, tzinfo=timezone.utc), skip_gate)

    def test_current_main_at_revision_time_publishes(self):
        self.assertEqual(self.stale(), {})
        self.assertEqual(self.stale(releases=self.releases + [
            {"tagName": "v1.0.0.snapshot.20261105125000", "isDraft": False}]), {})

    def test_moved_main_skips_stale_build(self):
        self.assertEqual(self.stale(current="newer-main"),
                         {"skip": "main moved from current-main to newer-main"})

    def test_publish_before_revision_time_is_error(self):
        self.assertIn("before its revision time", self.stale(minute=49)["error"])

    def test_newer_snapshot_inside_gate_is_error(self):
        newer = self.releases + [{"tagName": "v1.0.0.snapshot.20261105124000", "isDraft": False}]
        self.assertIn("within 50 minutes", self.stale(releases=newer)["error"])
        self.assertEqual(self.stale(releases=newer, skip_gate=True), {})

    def run_main(self, event, commit, command=None, env=None):
        pages = json.dumps([[{"tag_name": r["tagName"], "draft": r["isDraft"]} for r in self.releases]])
        clock = unittest.mock.Mock()
        clock.now.return_value = datetime(2026, 11, 5, 12, 30, tzinfo=timezone.utc)
        stream = io.StringIO()
        with patch.dict(os.environ, GITHUB_EVENT_NAME=event, SKIP_GATE="false", **(env or {})), \
                patch.object(snapshot, "run", side_effect=["", "current-main", pages, commit]), \
                patch.object(snapshot, "output") as output, patch.object(snapshot, "datetime", clock), \
                patch.object(snapshot.time, "sleep") as sleep, contextlib.redirect_stdout(stream):
            clock.strptime = datetime.strptime
            status = snapshot.main(command)
        return status, stream.getvalue(), sleep, output

    def test_dispatch_gate_exits_green_with_notice(self):
        status, log, sleep, output = self.run_main("workflow_dispatch", "old")
        self.assertEqual(status, 0)
        self.assertIn("::notice::", log)
        self.assertIn("current-main", log)
        self.assertIn("2026-11-05 12:50:00 UTC", log)
        output.assert_not_called()

    def test_dispatch_unchanged_exits_red(self):
        status, log, sleep, output = self.run_main("workflow_dispatch", "current-main")
        self.assertEqual(status, 1)
        self.assertIn("::error::Snapshot skipped: unchanged main current-main", log)

    def test_push_plans_without_sleeping(self):
        status, log, sleep, output = self.run_main("push", "old", env={"GITHUB_RUN_NUMBER": "7"})
        self.assertEqual(status, 0)
        sleep.assert_not_called()
        output.assert_called_once_with(tag="v1.0.0.snapshot.20261105125000",
                                       version="1.0.0.snapshot.20261105125000", build="7", main="current-main")

    def test_wait_sleeps_until_revision(self):
        status, log, sleep, output = self.run_main(
            "push", "old", "wait", {"TAG": "v1.0.0.snapshot.20261105125000"})
        self.assertEqual(status, 0)
        sleep.assert_called_once_with(1200.0)

    def test_check_skips_moved_main_with_notice(self):
        status, log, sleep, output = self.run_main(
            "push", "old", "check", {"TAG": "v1.0.0.snapshot.20261105123000", "MAIN": "older-main"})
        self.assertEqual(status, 0)
        self.assertIn("::notice::Snapshot skipped: main moved from older-main to current-main", log)
        output.assert_not_called()

if __name__ == "__main__":
    unittest.main()
