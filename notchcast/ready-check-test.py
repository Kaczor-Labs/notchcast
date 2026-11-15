#!/usr/bin/env python3
"""Verify ready-check.sh covers every pr.yml step and reports PASS or the first failing gate."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/pr.yml"
SCRIPT = ROOT / "notchcast/ready-check.sh"
# Every step of pr.yml and of the local actions it uses, and how ready-check.sh covers it.
COVERED = {
    ("pr.yml:route", "actions/checkout"): "runner routing; no gate",
    ("pr.yml:route", "./notchcast/actions/route"): "runner routing; no gate",
    ("pr.yml:checks", "actions/checkout"): "the shared clone at HEAD",
    ("pr.yml:checks", "Shared PR build lane"): "ci-build.sh, unsharded",
    ("pr.yml:harnesses", "actions/checkout"): "the shared clone at HEAD",
    ("pr.yml:harnesses", "./tools/notchcast/actions/xcode"): "ci-build.sh's xcode step",
    ("pr.yml:harnesses", "./tools/notchcast/actions/tests"): "ci-build.sh's harnesses step",
    ("pr.yml:build", "A train run names its base"): "train branches only",
    ("pr.yml:build", "Checks and every harness shard passed"): "aggregate of the two above",
    ("pr.yml:build", "actions/checkout"): "records the tree; no gate",
    ("pr.yml:build", "Record the tested tree"): "records the tree; no gate",
    ("pr.yml:build", "actions/upload-artifact"): "records the tree; no gate",
    ("xcode", 'source "$GITHUB_ACTION_PATH/../../ci-xcode.sh"'): "ci-build.sh sources ci-xcode.sh",
    ("tests", "cache"): "harness binary cache; no gate",
    ("tests", "actions/cache/restore"): "harness binary cache; no gate",
    ("tests", 'bash "$GITHUB_ACTION_PATH/../../ci-tests.sh"'): "ci-build.sh runs ci-tests.sh",
    ("tests", "Failed harness logs"): "logs only; ready-check keeps the whole log",
    ("tests", "Compiled harness cache"): "harness binary cache; no gate",
    ("tests", "actions/cache/save"): "harness binary cache; no gate",
}


def steps(path, step_indent):
    """(job, step text) for each step; a composite action has one job, its own."""
    job, found, current = None, [], None
    for line in path.read_text().splitlines():
        if match := re.fullmatch(r"  ([\w-]+):", line):
            job, current = match[1], None
        elif line.startswith(" " * step_indent + "- "):
            current = [line[step_indent + 2:]]
            found.append((job, current))
        elif current is not None and line.startswith(" " * (step_indent + 2)):
            current.append(line[step_indent + 2:])
        elif line.strip() and not line.startswith(" " * (step_indent + 2)):
            current = None
    return [(job, "\n".join(text)) for job, text in found]


def field(text, key):
    match = re.search(rf"^{key}: (.+)$", text, re.M)
    return match[1].strip() if match else None


def signature(text):
    if uses := field(text, "uses"):
        return uses.split("@")[0].split(" #")[0]
    return field(text, "name") or field(text, "id") or field(text, "run")


def env(text):
    block = re.search(r"^env:\n((?:  .+\n?)+)", text, re.M)
    return dict(re.findall(r"^  (\w+): (.+)$", block[1], re.M)) if block else {}


class CoverageTest(unittest.TestCase):
    def all_steps(self):
        found = [(f"pr.yml:{job}", text) for job, text in steps(WORKFLOW, 6)]
        for action in ("xcode", "tests"):
            found += [(action, text) for _, text in steps(ROOT / f"notchcast/actions/{action}/action.yml", 4)]
        return found

    def test_every_step_is_covered(self):
        found = {(scope, signature(text)) for scope, text in self.all_steps()}
        self.assertEqual(found - COVERED.keys(), set(), "a pr.yml step ready-check.sh does not cover")
        self.assertEqual(COVERED.keys() - found, set(), "COVERED names a step pr.yml no longer has")

    def test_the_build_lane_is_ci_build(self):
        lane = next(text for scope, text in self.all_steps() if signature(text) == "Shared PR build lane")
        self.assertEqual(field(lane, "run"), "bash ../tools/notchcast/ci-build.sh")
        self.assertEqual(set(env(lane)), {"BASE_SHA", "HEAD_SHA", "NOTCHCAST_HARNESSES_SHARDED"})
        script = SCRIPT.read_text()
        self.assertIn("export BASE_SHA HEAD_SHA", script)
        self.assertIn("unset NOTCHCAST_HARNESSES_SHARDED", script)
        self.assertIn("bash notchcast/ci-build.sh", script)

    def test_the_harness_step_matches_ci_build(self):
        ci_build = (ROOT / "notchcast/ci-build.sh").read_text()
        self.assertIn('source "$TOOLS/notchcast/ci-xcode.sh"', ci_build)
        self.assertRegex(ci_build, r'NOTCHCAST_HARNESSES_SHARDED.*\n.*\n\s*bash "\$TOOLS/notchcast/ci-tests.sh"')
        run = next(text for scope, text in self.all_steps() if scope == "tests" and "ci-tests.sh" in text)
        ci_tests = (ROOT / "notchcast/ci-tests.sh").read_text()
        # Input-driven variables default to the whole suite; a fixed value must be one ci-tests.sh sets itself.
        for name, value in env(run).items():
            if "${{" not in value:
                self.assertRegex(ci_tests, rf"export .*\b{name}={value.strip(chr(39))}\b")


# Machine git config (init.defaultBranch, signing, url rewrites) never reaches the fixture repos.
GIT_ISOLATED = {"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}


class BehaviourTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="ready-check-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.repo = self.root / "repo"
        (self.repo / "notchcast").mkdir(parents=True)
        (self.root / "home").mkdir()
        shutil.copy(SCRIPT, self.repo / "notchcast/ready-check.sh")
        (self.repo / "notchcast/config.env").write_text("FORK_REPO=example/fork\n")
        (self.repo / "notchcast/ci-build.sh").write_text(
            'for s in xcode build lint; do echo "$s" > "$RUNNER_TEMP/step"; [ ! -e "fail-$s" ] || exit 1; done\n'
            'echo "base=$BASE_SHA head=$HEAD_SHA sharded=${NOTCHCAST_HARNESSES_SHARDED:-} pwd=$PWD"\n')
        self.git("init", "-q", "-b", "main")
        self.commit("base")
        self.git("tag", "base")
        bare = self.root / "fork.git"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True,
                       env={**os.environ, **GIT_ISOLATED})
        self.git("push", "-q", str(bare), "main", "base")
        self.env = {**os.environ, **GIT_ISOLATED, "HOME": str(self.root / "home"), "GIT_CONFIG_COUNT": "1",
                    "GIT_CONFIG_KEY_0": f"url.{bare}.insteadOf", "GIT_CONFIG_VALUE_0": "https://github.com/example/fork.git",
                    "NOTCHCAST_HARNESSES_SHARDED": "1"}

    def git(self, *arguments):
        return subprocess.run(["git", "-C", str(self.repo), *arguments], check=True, capture_output=True,
                              text=True, env={**os.environ, **GIT_ISOLATED, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                                              "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}).stdout.strip()

    def commit(self, message, path=None):
        if path:
            (self.repo / path).write_text(message)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def check(self, *arguments):
        return subprocess.run(["bash", "notchcast/ready-check.sh", *arguments], cwd=self.repo, env=self.env,
                              capture_output=True, text=True)

    def test_pass_builds_head_against_the_base(self):
        self.commit("work", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(result.stdout.splitlines()[-1], f"PASS {head[:12]} against base ({self.git('rev-parse', 'base')[:12]})")
        log = (self.root / "home/Library/Caches/notchcast/ready-check" / f"{head[:12]}.log").read_text()
        self.assertIn(f"base={self.git('rev-parse', 'base')} head={head} sharded= ", log)
        self.assertNotIn(str(self.repo), log.split("pwd=")[1], "the build must run in a clone outside the checkout")

    def test_pass_names_retried_and_ignored_harnesses(self):
        lines = self.check("base").stdout.splitlines()
        self.assertEqual(lines[-3:-1], ["retried: none", "ignored (fails upstream too): none"])
        (self.repo / "notchcast/ci-build.sh").write_text(
            "printf '::warning::retrying %s alone\\n' BTests ATests BTests\n"
            "echo '::warning::BTests fails on upstream abc1234 too; not ours, ignored'\n")
        self.commit("retries")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[-3:-1], ["retried: ATests BTests", "ignored (fails upstream too): BTests"])
        self.assertTrue(lines[-1].startswith("PASS "))

    def test_the_parsed_lines_are_the_ones_ci_tests_prints(self):
        ci_tests = (ROOT / "notchcast/ci-tests.sh").read_text()
        self.assertIn('echo "::warning::retrying $name alone"', ci_tests)
        self.assertIn('echo "::warning::$name fails on upstream ${UPSTREAM:0:7} too; not ours, ignored"', ci_tests)

    def test_fail_names_the_first_failing_gate(self):
        self.commit("break", "fail-build")
        result = self.check("base")
        self.assertEqual(result.returncode, 1)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL build; log: ")

    def test_refuses_uncommitted_changes_and_unknown_bases(self):
        (self.repo / "notchcast/config.env").write_text("FORK_REPO=example/other\n")
        self.assertIn("FAIL setup: uncommitted", self.check("base").stderr)
        self.git("checkout", "--", ".")
        self.assertIn("FAIL setup: no commit nope", self.check("nope").stderr)


if __name__ == "__main__":
    unittest.main()
