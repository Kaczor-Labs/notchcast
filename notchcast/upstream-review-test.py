#!/usr/bin/env python3
"""Sync's plan moves main onto new upstream only with the repo owner's passing review status on that upstream commit."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("ci", Path(__file__).with_name("ci.py"))
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)
CONTEXT, OWNER, BOT = "test/review", "fork", "github-actions[bot]"
CFG = {"UPSTREAM_REPO": "up/stream", "FORK_REPO": "fork/repo", "TESTED_CONTEXT": "test/tested",
       "REVIEW_CONTEXT": CONTEXT, "REVIEW_LABEL": "upstream-sync", "BASELINE_TAG": "v0.0.1"}
REAL_RUN = CI.run


def status(state, creator=OWNER, context=CONTEXT):
    return {"context": context, "state": state, "creator": {"login": creator}}


class PlanReviewGateTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        root = Path(self.scratch.name)
        self.up, self.main, fork = root / "up", root / "main", root / "fork.git"
        self.git(root, "init", "-q", "-b", "main", str(self.up))
        self.u0 = self.commit(self.up, {"a.txt": "a\n", ".github/workflows/ci.yml": "on: push\n"}, "upstream base")
        self.git(self.up, "tag", "v0.0.1")
        self.git(self.main, "clone", "-q", str(self.up), str(self.main), cwd=root)
        self.commit(self.main, {"ours.txt": "ours\n"}, "Notchcast: ours")
        self.u1 = self.commit(self.up, {"b.txt": "b\n", ".github/workflows/ci.yml": "on: [push, pull_request]\n"},
                              "upstream change")
        self.git(self.up, "tag", "-a", "-m", "release", "v0.0.2")
        self.git(root, "init", "-q", "--bare", str(fork))
        self.urls = {"https://github.com/up/stream.git": str(self.up), "https://github.com/fork/repo.git": str(fork)}
        self.statuses, self.review_prs = {}, []
        self.cwd = os.getcwd()
        os.chdir(self.main)

    def tearDown(self):
        os.chdir(self.cwd)
        self.scratch.cleanup()

    @staticmethod
    def git(repo, *args, cwd=None):
        return REAL_RUN("git", *args, cwd=cwd or repo, env={"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_AUTHOR_NAME": "T",
                                                             "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "T",
                                                             "GIT_COMMITTER_EMAIL": "t@example.com"})

    def commit(self, repo, files, message):
        for name, text in files.items():
            (repo / name).parent.mkdir(parents=True, exist_ok=True)
            (repo / name).write_text(text)
        self.git(repo, "add", ".")
        self.git(repo, "-c", "core.hooksPath=/dev/null", "commit", "-qm", message)
        return self.git(repo, "rev-parse", "HEAD")

    def gh(self, cmd):
        args = " ".join(cmd)
        if "/statuses?" in args:
            sha = cmd[-1].split("/")[4]
            if sha not in self.statuses:
                raise subprocess.CalledProcessError(1, cmd, "No commit found for SHA")
            return json.dumps([self.statuses[sha]])
        if "/releases?" in args:
            return "[[]]"
        if args.startswith("gh release list"):
            return json.dumps([{"tagName": tag, "name": tag, "isDraft": False, "isPrerelease": False}
                               for tag in ("v0.0.1", "v0.0.2")])
        if args.endswith("/status"):
            return json.dumps({"statuses": [{"context": "test/tested", "state": "success"}]})
        if args.startswith("gh pr list") and "--label" in cmd:
            return json.dumps(self.review_prs)
        if args.startswith("gh pr list"):
            return "[]"
        raise AssertionError(f"unexpected gh call: {args}")

    def plan(self):
        def fake(*cmd, cwd=None, env=None):
            if cmd[0] == "gh":
                return self.gh(cmd)
            return REAL_RUN(*(self.urls.get(arg, arg) for arg in cmd), cwd=cwd, env=env)
        with tempfile.NamedTemporaryFile("r") as out, mock.patch.object(CI, "run", fake), \
                mock.patch.object(CI, "config", return_value=CFG), mock.patch.dict(os.environ, {"GITHUB_OUTPUT": out.name}), \
                mock.patch("builtins.print"):
            CI.plan()
            values = dict(line.rstrip("\n").split("=", 1) for line in out)
        values["releases"] = [release["tag"] for release in json.loads(values["releases"])]
        return values

    def test_no_record_never_moves_main(self):
        for statuses in ({}, {self.u1: []}):
            with self.subTest(statuses=statuses):
                self.statuses = statuses
                result = self.plan()
                self.assertEqual((result["rebase"], result["stage"]), ("false", "open"))
                self.assertEqual(result["upstream_main"], self.u1)

    def test_failure_never_moves_main(self):
        for statuses in ([status("failure")], [status("failure"), status("success")], [status("pending")]):
            with self.subTest(statuses=statuses):
                self.statuses = {self.u1: statuses}
                self.assertEqual(self.plan()["rebase"], "false")

    def test_success_for_another_commit_never_moves_main(self):
        self.statuses = {self.u0: [status("success")], "f" * 40: [status("success")], self.u1: []}
        self.assertEqual(self.plan()["rebase"], "false")

    def test_success_from_anyone_but_the_owner_never_moves_main(self):
        for statuses in ([status("success", BOT)], [status("success", "someone")],
                         [status("success", context="test/tested")], [status("success", BOT), status("failure")]):
            with self.subTest(statuses=statuses):
                self.statuses = {self.u1: statuses}
                self.assertEqual(self.plan()["rebase"], "false")

    def test_owner_success_moves_main(self):
        for statuses in ([status("success", "Fork")], [status("success"), status("failure")],
                         [status("failure", BOT), status("success")]):
            with self.subTest(statuses=statuses):
                self.statuses = {self.u1: statuses}
                result = self.plan()
                self.assertEqual((result["rebase"], result["stage"]), ("true", ""))
                self.assertEqual(result["upstream_main"], self.u1)

    def test_release_waits_for_its_upstream_commit_to_be_reviewed(self):
        self.assertEqual(self.plan()["releases"], ["v0.0.1"])
        self.statuses = {self.u1: [status("success")]}
        self.assertEqual(self.plan()["releases"], ["v0.0.1", "v0.0.2"])

    def test_review_pr_closes_once_main_holds_upstream(self):
        self.git(self.up, "update-ref", "refs/heads/main", self.u0)
        self.assertEqual(self.plan()["stage"], "")
        self.review_prs = [{"number": 9}]
        result = self.plan()
        self.assertEqual((result["rebase"], result["stage"]), ("false", "close"))

    def test_review_pr_shows_upstream_diff_without_workflows(self):
        self.git(self.main, "fetch", "-q", str(self.up), "main")
        with mock.patch.dict(os.environ, {"GIT_CONFIG_GLOBAL": "/dev/null"}):
            first = CI.review_commits(self.u0, self.u1)
            self.assertEqual(first, CI.review_commits(self.u0, self.u1))
        review_base, head = first
        self.assertEqual(self.git(self.main, "rev-parse", f"{review_base}^@").split(), [self.u0])
        self.assertEqual(self.git(self.main, "rev-parse", f"{head}^@").split(), [review_base, self.u1])
        self.assertEqual(self.git(self.main, "diff", "--name-status", review_base, head), "A\tb.txt")
        for commit in first:
            self.assertNotIn(".github", self.git(self.main, "ls-tree", "-r", "--name-only", commit))
        body = CI.review_body(self.u0, self.u1, CFG)
        self.assertIn(f"gh api -X POST repos/fork/repo/statuses/{self.u1} -f context={CONTEXT} -f state=success", body)
        self.assertIn(f"{self.u0}..{self.u1}", body)


if __name__ == "__main__":
    unittest.main()
