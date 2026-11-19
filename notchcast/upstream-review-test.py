#!/usr/bin/env python3
"""Sync moves main onto new upstream, and signs a release, only with the repo owner's passing review of that commit."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import textwrap
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
ROOT = Path(__file__).resolve().parent.parent


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
        self.statuses, self.review_prs, self.upstream_releases = {}, [], ["v0.0.1", "v0.0.2"]
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
                               for tag in self.upstream_releases])
        if args.endswith("/status"):
            return json.dumps({"statuses": [{"context": "test/tested", "state": "success"}]})
        if args.startswith("gh pr list") and "--label" in cmd:
            return json.dumps(self.review_prs)
        if args.startswith("gh pr list"):
            return "[]"
        raise AssertionError(f"unexpected gh call: {args}")

    def fake_run(self, *cmd, cwd=None, env=None):
        if cmd[0] == "gh":
            return self.gh(cmd)
        return REAL_RUN(*(self.urls.get(arg, arg) for arg in cmd), cwd=cwd, env=env)

    def ci(self, function, *args):
        with mock.patch.object(CI, "run", self.fake_run), mock.patch.object(CI, "config", return_value=CFG), \
                mock.patch("builtins.print"):
            return function(*args)

    def plan(self):
        with tempfile.NamedTemporaryFile("r") as out, mock.patch.dict(os.environ, {"GITHUB_OUTPUT": out.name}):
            self.ci(CI.plan)
            values = dict(line.rstrip("\n").split("=", 1) for line in out)
        releases = json.loads(values["releases"])
        values["releases"] = [release["tag"] for release in releases]
        values["commits"] = {release["tag"]: release.get("commit") for release in releases}
        return values

    def exit_code(self, function, *args):
        with self.assertRaises(SystemExit) as raised:
            self.ci(function, *args)
        return raised.exception.code

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

    def test_tagged_ancestor_of_reviewed_upstream_is_not_released(self):
        parent = self.commit(self.up, {"evil.sh": "x\n", ".github/workflows/evil.yml": "on: push\n"}, "parent")
        self.git(self.up, "tag", "-a", "-m", "release", "v0.0.3")
        self.git(self.up, "rm", "-q", "evil.sh", ".github/workflows/evil.yml")
        child = self.commit(self.up, {}, "child deletes it")
        self.upstream_releases = ["v0.0.1", "v0.0.2", "v0.0.3"]
        self.statuses = {child: [status("success")]}
        result = self.plan()
        self.assertEqual((result["rebase"], result["upstream_main"]), ("true", child))
        self.assertEqual(result["releases"], ["v0.0.1"])
        self.statuses[parent] = [status("success")]
        self.assertEqual(self.plan()["releases"], ["v0.0.1", "v0.0.3"])

    def test_release_pins_the_commit_plan_cleared(self):
        self.statuses = {self.u1: [status("success")]}
        self.assertEqual(self.plan()["commits"], {"v0.0.1": self.u0, "v0.0.2": self.u1})
        self.assertIsNone(self.ci(CI.pin_tag, "v0.0.2", self.u1))
        self.assertEqual(self.git(self.main, "rev-parse", "refs/remotes/upstream/main"), self.u1)
        moved = self.commit(self.up, {"c.txt": "c\n"}, "after plan")
        self.git(self.up, "tag", "-f", "-a", "-m", "moved", "v0.0.2", moved)
        self.assertIn("moved tag v0.0.2", str(self.exit_code(CI.pin_tag, "v0.0.2", self.u1)))

    def test_main_push_rereads_the_review(self):
        for statuses, code in (([status("success")], 0), ([status("failure"), status("success")], 1),
                               ([status("success", BOT)], 1), (None, 1)):
            with self.subTest(statuses=statuses):
                self.statuses = {} if statuses is None else {self.u1: statuses}
                self.assertEqual(self.exit_code(CI.reviewed, self.u1), code)
        workflow = (Path(__file__).parent.parent / ".github/workflows/sync.yml").read_text()
        jobs = workflow.split("\njobs:\n", 1)[1]
        build = jobs.split("\n  main:\n", 1)[1].split("\n  push:\n", 1)[0]
        self.assertLess(build.index("ci.py reviewed"), build.index("ci.py replay"))
        self.assertNotIn("secrets.", build)
        push = jobs.split("\n  push:\n", 1)[1].split("\n  failed:\n", 1)[0]
        self.assertLess(push.index('ci.py reviewed "$UP"'), push.index("actions/deploy-key"))
        self.assertLess(push.index("actions/deploy-key"), push.index("push --atomic"))
        self.assertIn("UP: ${{ needs.plan.outputs.upstream_main }}", push)

    def test_release_rereads_a_side_commit_review_before_tests_and_signing(self):
        self.statuses = {self.u1: [status("success")]}
        result = self.plan()
        self.assertEqual((result["base"], result["commits"]), (self.u0, {"v0.0.1": self.u0, "v0.0.2": self.u1}))
        workflow = (ROOT / ".github/workflows/sync-release.yml").read_text()
        self.assertIn("\n  COMMIT: ${{ inputs.commit }}\n", workflow.split("\njobs:\n", 1)[0])
        job = workflow.split("\n  build:\n", 1)[1].split("\n  sign:\n", 1)[0]
        self.assertIn("statuses: read", job.split("steps:", 1)[0])
        step = job.split("- name: Re-read the tag commit's review", 1)[1].split("\n      - ", 1)[0]
        self.assertLess(job.index("Re-read the tag commit's review"), job.index("ci.py pin-tag"))
        self.assertLess(job.index("Re-read the tag commit's review"), job.index("actions/tests"))
        self.assertIn("BASE: ${{ inputs.base }}", step)
        publish = workflow.split("\n  publish:\n", 1)[1]
        self.assertLess(publish.index("Re-read the tag commit's review"), publish.index("actions/deploy-key"))
        script = textwrap.dedent(step.split("run: |\n", 1)[1])
        cfg, root = CI.config(), Path(self.scratch.name)
        owner = cfg["FORK_REPO"].split("/")[0]
        (root / "tools").symlink_to(ROOT)
        (root / "bin").mkdir()
        (root / "bin/gh").write_text(f'#!/bin/sh\necho "$*" >> {root}/gh-calls\ncat {root}/statuses.json\n')
        (root / "bin/gh").chmod(0o755)

        def release_step(commit, statuses):
            (root / "gh-calls").unlink(missing_ok=True)
            (root / "statuses.json").write_text(json.dumps([[{"context": cfg["REVIEW_CONTEXT"], "state": state,
                                                               "creator": {"login": owner}} for state in statuses]]))
            env = dict(os.environ, PATH=f"{root}/bin:{os.environ['PATH']}", COMMIT=commit, BASE=self.u0)
            done = subprocess.run(["bash", "-e", "-c", script], cwd=root, env=env, capture_output=True, text=True)
            return done.returncode, (root / "gh-calls").exists()

        self.assertEqual(release_step(self.u1, ["success"]), (0, True))
        self.assertEqual(release_step(self.u1, ["failure", "success"])[0], 1)
        self.assertEqual(release_step(self.u1, [])[0], 1)
        self.assertEqual(release_step(self.u0, ["failure"]), (0, False))

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
