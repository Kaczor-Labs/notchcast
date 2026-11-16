#!/usr/bin/env python3
"""Verify ready-check.sh covers every pr.yml step and reports PASS or the first failing gate."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


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


# A builder's own NOTCHCAST_READY_BRANCH would judge every fixture as that branch.
def fixture_env(extra):
    return {**{k: v for k, v in os.environ.items() if k != "NOTCHCAST_READY_BRANCH"}, **GIT_ISOLATED, **extra}


# Fails when the judged tree has drift-fail; records its arguments and what origin/main resolves to.
DRIFT_STUB = """import subprocess, sys
from pathlib import Path
root = Path(sys.argv[sys.argv.index('--root') + 1])
main = subprocess.run(['git', '-C', str(root), 'rev-parse', 'refs/remotes/origin/main'],
                      capture_output=True, text=True).stdout.strip()
print('drift', *sys.argv[1:], 'main=' + main)
sys.exit((root / 'drift-fail').exists())
"""


# Fails when the judged tree has delete-fail; prints its arguments as the delete test's verdict line.
DELETE_STUB = """import sys
from pathlib import Path
verdict = 'FAIL' if Path('delete-fail').exists() else 'PASS'
print(verdict, 'delete Stub', *sys.argv[1:])
sys.exit(verdict == 'FAIL')
"""


class BehaviourTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="ready-check-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.repo = self.root / "repo"
        (self.repo / "notchcast").mkdir(parents=True)
        (self.root / "home").mkdir()
        shutil.copy(SCRIPT, self.repo / "notchcast/ready-check.sh")
        (self.repo / "notchcast/config.env").write_text("FORK_REPO=example/fork\nUPSTREAM_REPO=example/upstream\n"
                                                       "MAINTAINER_NAME=t\nMAINTAINER_EMAIL=t@t\n")
        for tool in ("check-identity.sh", "check-identity.py", "check-commit-emails.py", "ci.py"):
            shutil.copy(ROOT / "notchcast" / tool, self.repo / "notchcast" / tool)
        (self.repo / "notchcast/ci-build.sh").write_text(
            'for s in xcode build lint; do echo "$s" > "$RUNNER_TEMP/step"; [ ! -e "fail-$s" ] || exit 1; done\n'
            'echo "base=$BASE_SHA head=$HEAD_SHA sharded=${NOTCHCAST_HARNESSES_SHARDED:-} pwd=$PWD"\n')
        shutil.copy(ROOT / "notchcast/drift-gates.sh", self.repo / "notchcast/drift-gates.sh")
        (self.repo / "notchcast/check-addon-delete.py").write_text(DELETE_STUB)
        (self.repo / "notchcast/check-drift.py").write_text(DRIFT_STUB)
        self.git("init", "-q", "-b", "main")
        self.commit("base")
        self.git("tag", "base")
        bare = self.root / "fork.git"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True,
                       env={**os.environ, **GIT_ISOLATED})
        self.git("push", "-q", str(bare), "main", "base")
        upstream = self.upstream = self.root / "upstream.git"
        subprocess.run(["git", "clone", "-q", "--bare", str(bare), str(upstream)], check=True,
                       env={**os.environ, **GIT_ISOLATED})
        self.env = fixture_env({"HOME": str(self.root / "home"), "GIT_CONFIG_COUNT": "2",
                                "GIT_CONFIG_KEY_0": f"url.{bare}.insteadOf",
                                "GIT_CONFIG_VALUE_0": "https://github.com/example/fork.git",
                                "GIT_CONFIG_KEY_1": f"url.{upstream}.insteadOf",
                                "GIT_CONFIG_VALUE_1": "https://github.com/example/upstream.git",
                                "NOTCHCAST_HARNESSES_SHARDED": "1"})

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

    def test_runs_land_drift_gates_against_the_base(self):
        self.commit("work", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        base = self.git("rev-parse", "base")
        log = (self.root / "home/Library/Caches/notchcast/ready-check" / f"{self.git('rev-parse', 'HEAD')[:12]}.log").read_text()
        self.assertRegex(log, rf"drift --root \S+ --compare-base {base} main={base}\n")
        self.assertRegex(log, rf"drift --root \S+ main={base}\n")

    def test_drift_fails_with_the_base_tools(self):
        (self.repo / "notchcast/check-drift.py").write_text("import sys; sys.exit(0)\n")
        (self.repo / "drift-fail").write_text("")
        self.commit("drift and a weakened gate")
        result = self.check("base")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL drift; log: ")
        self.assertIn("REFUSED: drift", result.stdout)

    def test_private_data_added_by_the_branch_fails(self):
        home = "/" + "Users/" + "someone/notes.txt"
        self.commit(f"path {home}\n", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("check-identity: work.txt:1: <home-path>\n", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; log: ")
        self.git("reset", "-q", "--hard", "base")
        self.git("commit", "-q", "--allow-empty", "-m", f"moved {home}")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: metadata names something private; ")
        self.git("reset", "-q", "--hard", "base")
        self.commit("clean", "clean.txt")
        self.assertEqual(self.check("base").returncode, 0)

    def test_a_disabled_scanner_fails_with_the_base_one(self):
        (self.repo / "notchcast/check-identity.sh").write_text("exit 0\n")
        (self.repo / "notchcast/check-identity.py").write_text("raise SystemExit(0)\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertNotIn("identity: bootstrap", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_pythonpath_cannot_run_code_in_the_base_scanner(self):
        config = self.repo / "notchcast/config.env"
        config.write_text(config.read_text() + 'export PYTHONPATH="$PWD/notchcast/injected"\n')
        (self.repo / "notchcast/injected").mkdir()
        (self.repo / "notchcast/injected/sitecustomize.py").write_text("import os\nos._exit(0)\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_binary_attribute_still_scans_the_text(self):
        (self.repo / ".gitattributes").write_text("work.txt -diff\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertIn("check-identity: work.txt:1: <home-path>\n", result.stdout)
        self.assertIn("check-identity: work.txt:1 (commit addition): <home-path>\n", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_base_scanner_without_text_still_fails_through_heads(self):
        scanner = self.repo / "notchcast/check-identity.py"
        scanner.write_text(scanner.read_text().replace('"--text", ', ""))
        self.commit("old scanner")
        self.git("tag", "-f", "base")
        shutil.copy(ROOT / "notchcast/check-identity.py", scanner)
        (self.repo / ".gitattributes").write_text("work.txt -diff\n")
        (self.repo / "work.txt").write_text("path " + "/" + "Users/someone/notes.txt\n")
        self.commit("binary work")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_path_cannot_replace_the_scanners_python(self):
        config = self.repo / "notchcast/config.env"
        config.write_text(config.read_text() + 'export PATH="$PWD/notchcast/bin:$PATH"\n')
        (self.repo / "notchcast/bin").mkdir()
        (self.repo / "notchcast/bin/python3").write_text(
            f'#!/bin/bash\n[ "$1" != -I ] || exit 0\nexec {shutil.which("python3")} "$@"\n')
        (self.repo / "notchcast/bin/python3").chmod(0o755)
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_git_config_cannot_drop_the_base_scanner(self):
        config = self.repo / "notchcast/config.env"
        config.write_text(config.read_text() + "export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_2=core.attributesFile\n"
                          'export GIT_CONFIG_VALUE_2="$PWD/notchcast/attributes"\n')
        (self.repo / "notchcast/attributes").write_text("check-identity.py export-ignore\n")
        (self.repo / "notchcast/check-identity.py").write_text("raise SystemExit(0)\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertNotIn("identity: bootstrap", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_base_without_a_scanner_bootstraps_from_head(self):
        self.git("rm", "-q", "notchcast/check-identity.py")
        self.commit("no scanner")
        self.git("tag", "bare")
        self.git("checkout", "-q", "base", "--", "notchcast/check-identity.py")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("bare")
        self.assertIn("identity: bootstrap, scanner from HEAD\n", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_an_upstream_line_passes_and_a_fork_added_home_path_fails(self):
        fixture, line = self.repo / "Tests/Fixture.swift", 'let path = "/' + 'Users/x/notes.md"\n'
        fixture.parent.mkdir()
        fixture.write_text(line)
        self.commit("upstream fixture")
        self.git("push", "-q", str(self.upstream), "HEAD:main")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        fixture.write_text(line + line.replace("x/", "y/"))
        self.commit("fork fixture")
        result = self.check("base")
        self.assertIn("check-identity: Tests/Fixture.swift:2: <home-path>\n", result.stdout)
        self.assertNotIn("Tests/Fixture.swift:1", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_prints_the_upstream_footprint_and_its_delta(self):
        self.commit("work", "work.txt")
        self.commit("stock edit", "notchcast/ci-build.sh")
        self.git("rm", "-q", "notchcast/drift-gates.sh")
        self.commit("stock delete")
        deleted = 2 + len((ROOT / "notchcast/drift-gates.sh").read_text().splitlines())
        result = self.check("base")
        base = self.git("rev-parse", "base")
        self.assertIn(f"upstream touch: 2 files, +1 −{deleted} (base {base[:12]})\n"
                      f"delta: +2 files, +{deleted + 1} lines\n",
                      result.stdout)

    def test_an_addon_may_not_touch_upstream_paths(self):
        self.commit("own", "addon.txt")
        self.env["NOTCHCAST_READY_BRANCH"] = "v2/addons-zen"
        self.assertEqual(self.check("base").returncode, 0)
        self.commit("stock edit", "notchcast/ci-build.sh")
        result = self.check("base")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines()[-2:], ["notchcast/ci-build.sh",
                         "FAIL footprint: v2/addons-zen touches 1 upstream paths"])
        for core in ("v2/addons-core", "v2/addons-core-8"):
            self.env["NOTCHCAST_READY_BRANCH"] = core
            self.assertNotIn("FAIL footprint", self.check("base").stdout, core)
        self.env["NOTCHCAST_READY_BRANCH"] = "v2/addons-core-8-land"
        self.assertIn("FAIL footprint", self.check("base").stdout)

    def test_the_delete_test_runs_only_when_addon_code_changes(self):
        self.commit("work", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("delete", result.stdout)
        (self.repo / "Tinycast/Features/Notchcast/Stub").mkdir(parents=True)
        self.commit("addon", "Tinycast/Features/Notchcast/Stub/Stub.swift")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(result.stdout.splitlines()[-2:],
                         [f"addon-delete: PASS delete Stub --rotate --ref {head}",
                          f"PASS {head[:12]} against base ({self.git('rev-parse', 'base')[:12]})"])

    def test_a_failing_delete_test_fails_the_check(self):
        (self.repo / "Tinycast/Features/Notchcast/Stub").mkdir(parents=True)
        self.commit("addon", "Tinycast/Features/Notchcast/Stub/Stub.swift")
        self.commit("breach", "delete-fail")
        result = self.check("base")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.splitlines()[-2], f"FAIL delete Stub --rotate --ref {self.git('rev-parse', 'HEAD')}")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL addon-delete; log: ")

    def test_a_builders_branch_never_reaches_the_fixtures(self):
        with open(self.repo / "notchcast/check-drift.py", "a") as stub:
            stub.write("# stock edit\n")
        self.commit("stock edit")
        with mock.patch.dict(os.environ, NOTCHCAST_READY_BRANCH="v2/addons-zen"):
            self.env = fixture_env(self.env)
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAIL footprint", result.stdout)

    def test_drift_gates_are_land_sh_own(self):
        script = SCRIPT.read_text()
        self.assertIn('git show "$BASE_SHA:notchcast/drift-gates.sh"', script)
        self.assertIn('run_drift_gates "$BASE_SHA"', script)
        self.assertIn('source "$merge_tools/drift-gates.sh"', (ROOT / "notchcast/merge.sh").read_text())

    def test_refuses_uncommitted_changes_and_unknown_bases(self):
        (self.repo / "notchcast/config.env").write_text("FORK_REPO=example/other\n")
        self.assertIn("FAIL setup: uncommitted", self.check("base").stderr)
        self.git("checkout", "--", ".")
        self.assertIn("FAIL setup: no commit nope", self.check("nope").stderr)


if __name__ == "__main__":
    unittest.main()
