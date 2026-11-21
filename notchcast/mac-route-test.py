#!/usr/bin/env python3
"""Prove mac-route.py sends a PR to the MBP only when all hosted slots are busy and one MBP runner is idle."""
import importlib.util
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location("mac_route", Path(__file__).with_name("mac-route.py"))
route = importlib.util.module_from_spec(spec)
spec.loader.exec_module(route)


def job(labels, status="in_progress", group="GitHub Actions"):
    return {"labels": labels, "status": status, "runner_group_name": group}


def api_for(jobs_by_repo):
    """A canned API: each repo has one in-progress run holding the given jobs."""
    def api(path):
        if path.startswith("orgs/o/repos?"):
            return [{"full_name": f"o/{name}"} for name in jobs_by_repo]
        repo = path.split("/")[2]
        if path.endswith("/runs?status=in_progress&per_page=100"):
            return {"workflow_runs": [{"id": 1}]}
        return {"jobs": jobs_by_repo[repo]}
    return api


FIVE_BUSY = {"notchcast": [job(["xcode-27"])] * 3 + [job(["ubuntu-latest"])], "t3chad": [job(["macos-15"])] * 2}


class MacRouteTest(unittest.TestCase):
    def test_a_free_slot_stays_hosted(self):
        jobs = {"notchcast": [job(["xcode-27"])] * 4 + [job(["xcode-27"], status="queued")]}
        self.assertEqual(route.decide(api_for(jobs), "o", "pull_request", False), "would=hosted busy=4/5 mbp_idle=2")

    def test_five_busy_across_repos_overflow_to_an_idle_mbp(self):
        self.assertEqual(route.decide(api_for(FIVE_BUSY), "o", "pull_request", False), "would=mbp busy=5/5 mbp_idle=2")

    def test_both_mbp_runners_busy_stays_hosted(self):
        jobs = {**FIVE_BUSY, "notchcast": FIVE_BUSY["notchcast"] + [job([route.MBP_LABEL], group="Default")] * 2}
        self.assertEqual(route.decide(api_for(jobs), "o", "pull_request", False), "would=hosted busy=5/5 mbp_idle=0")

    def test_a_train_and_a_fork_always_stay_hosted(self):
        self.assertEqual(route.decide(api_for(FIVE_BUSY), "o", "workflow_dispatch", False), "would=hosted busy=5/5 mbp_idle=2")
        self.assertEqual(route.decide(api_for(FIVE_BUSY), "o", "pull_request", True), "would=hosted busy=5/5 mbp_idle=2")

    def test_an_api_error_stays_hosted_with_its_reason(self):
        def api(path):
            raise subprocess.CalledProcessError(1, ["gh", "api", path])
        line = route.decide(api, "o", "pull_request", False)
        self.assertTrue(line.startswith("would=hosted busy=?/5 mbp_idle=? reason=CalledProcessError: "), line)


if __name__ == "__main__":
    unittest.main()
