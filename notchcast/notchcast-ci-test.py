#!/usr/bin/env python3
"""bin/notchcast-ci.py with a fake `gh` first on PATH and a local bare origin: it pushes HEAD plainly with an upstream,
refuses without --keeper, dispatches nothing while a Main harnesses run waits to start, dispatches once and polls the run id the dispatch
response carries (never the latest run) until it completes, sleeps out an API rate limit, prints PASS/FAIL with the
changed harnesses, and refuses --no-push when origin's branch is not HEAD."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CI = Path(__file__).resolve().parent / "notchcast-ci.py"
URL = "https://github.com/Kaczor-Labs/notchcast/actions/runs/777"
FAKE_GH = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
d = Path(os.environ["FAKE_GH_DIR"])
sc = json.loads((d / "scenario.json").read_text())
args = sys.argv[1:]
with (d / "calls.log").open("a") as f:
    f.write(json.dumps(args) + "\\n")
if any(h in " ".join(args) for h in sc.get("hang", [])):
    __import__("time").sleep(60)
def count(name):
    n = int((d / name).read_text()) if (d / name).exists() else 0
    (d / name).write_text(str(n + 1))
    if n < sc.get("limited", {}).get(name, 0):
        sys.exit("gh: API rate limit exceeded for user ID 1 (HTTP 403)")
    return n - sc.get("limited", {}).get(name, 0)
if args[:2] == ["api", "rate_limit"] and args[-1].endswith(".remaining"):
    left = sc.get("remaining", [5000])
    n = int((d / "budget").read_text()) if (d / "budget").exists() else 0
    (d / "budget").write_text(str(n + 1))
    print(left[min(n, len(left) - 1)])
elif args[:2] == ["api", "rate_limit"]:
    print(0)  # a reset long past: no wait, whatever the real clock says
elif args[0] == "api":
    path = next(a for a in args if a.startswith("repos/"))
    if "/runs?" in path:
        query = dict(p.split("=") for p in path.split("?")[1].split("&"))
        state = sc["polls"][min(count("poll"), len(sc["polls"]) - 1)]
        workflow = path.split("/workflows/")[1].split("/")[0]
        runs = [{"id": r["id"], "status": r["status"], "html_url": "https://example.test/runs/%d" % r["id"]} for r in state
                if r["workflow"] == workflow and r["event"] == query["event"]][:int(query["per_page"])]
        print(json.dumps({"total_count": len(runs), "workflow_runs": runs}))
    elif "/dispatches" in path:
        print(json.dumps(sc["dispatch"]) if sc["dispatch"] is not None else "")
    elif "/actions/runs/" in path and args[-2:] == ["--jq", ".path"]:
        print(sc.get("run_path", ".github/workflows/main-harnesses.yml"))
    else:
        sys.exit("unexpected " + path)
elif args[:2] == ["run", "view"]:
    if "--json" in args:
        views = sc["view"] if isinstance(sc["view"], list) else [sc["view"]]
        print(json.dumps(views[min(count("view"), len(views) - 1)]))
    elif "--log-failed" in args:
        print(sc["log_failed"])
    elif "--log" in args:
        if "log" not in sc:
            sys.exit("log unavailable")
        print(sc["log"])
else:
    sys.exit("unexpected " + " ".join(args))
'''


# Runs notchcast-ci.py with its --max-wait timeout kept on the hung call alone, so a slow machine cannot time out another.
TIME_ONLY_THE_HUNG_CALL = '''
import runpy, subprocess, sys
hang, real_run = sys.argv.pop(1), subprocess.run
def run(cmd, **kwargs):
    if hang not in " ".join(cmd):
        kwargs["timeout"] = None
    return real_run(cmd, **kwargs)
subprocess.run = run
del sys.argv[0]
runpy.run_path(sys.argv[0], run_name="__main__")
'''


def run_state(run_id, status, workflow="main-harnesses.yml", event="workflow_dispatch"):
    return {"id": run_id, "status": status, "workflow": workflow, "event": event}


def log_line(text, step="Changed harnesses"):
    return f"harnesses\t{step}\t2026-11-09T10:00:00.1234567Z {text}"


SELECTED_LOG = "\n".join([
    log_line("##[group]Run git fetch -q origin", step="Changed harnesses"),
    log_line("if [ \"$GITHUB_EVENT_NAME\" = workflow_dispatch ]; then"),
    log_line("else"),
    log_line("fi"),
    log_line("##[endgroup]"),
    log_line("notchcast-core-test"),
    log_line("nc-Clock-model-test"),
    "harnesses\tRun harnesses, retry failures alone\t2026-11-09T10:05:00.1Z not-a-harness",
])


class CiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.fake = root / "fake"
        (root / "bin").mkdir()
        self.fake.mkdir()
        gh = root / "bin" / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.origin = root / "origin.git"
        self.repo = root / "repo"
        self.git(root, "init", "-q", "--bare", str(self.origin))
        self.git(root, "init", "-q", "-b", "feat", str(self.repo))
        self.commit("one")
        self.git(self.repo, "remote", "add", "origin", str(self.origin))
        self.hooks = self.repo.resolve() / ".git" / "notchcast-hooks"
        self.hooks.mkdir()
        pre_push = self.hooks / "pre-push"
        pre_push.write_text("#!/bin/sh\nexit 0\n")
        pre_push.chmod(0o755)
        self.git(self.repo, "config", "core.hooksPath", str(self.hooks))
        self.git(self.repo, "push", "-q", "origin", "feat")
        self.env = {**os.environ, "PATH": f"{root / 'bin'}{os.pathsep}{os.environ['PATH']}",
                    "FAKE_GH_DIR": str(self.fake), "NOTCHCAST_CI_POLL": "0.01",
                    "NOTCHCAST_CI_CLOCK": "virtual"}
        self.head = self.rev(self.repo, "HEAD")
        self.scenario(polls=[[]], dispatch={"workflow_run_id": 777, "html_url": URL},
                      view=self.view("success"), log=SELECTED_LOG, log_failed="")

    def rev(self, cwd, ref):
        return subprocess.run(["git", "-C", str(cwd), "rev-parse", ref], text=True, capture_output=True,
                              check=True).stdout.strip()

    def view(self, conclusion, status="completed", sha=None):
        return {"status": status, "conclusion": conclusion, "headSha": sha or self.head}

    def git(self, cwd, *args):
        subprocess.run(["git", "-C", str(cwd), "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True,
                       capture_output=True)

    def commit(self, name):
        (self.repo / name).write_text(name)
        self.git(self.repo, "add", name)
        self.git(self.repo, "commit", "-qm", name)

    def scenario(self, **values):
        path = self.fake / "scenario.json"
        current = {**(json.loads(path.read_text()) if path.exists() else {}), **values}
        if values.get("log", "") is None:
            del current["log"]
        path.write_text(json.dumps(current))

    def ci(self, *args, keeper=("--keeper",), **env):
        return subprocess.run([sys.executable, str(CI), "--repo", str(self.repo), *keeper, *args], text=True,
                              capture_output=True, env={**self.env, **env})

    def rerun(self):
        repo = self.repo.resolve()
        return f"python3 {repo}/notchcast/notchcast-ci.py --repo {repo} --keeper"

    def calls(self):
        path = self.fake / "calls.log"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def views(self):
        return [c for c in self.calls() if c[:2] == ["run", "view"] and "--json" in c]

    def passed(self, url=URL, sha=None):
        return f"PASS {url} at {(sha or self.head)[:12]} harnesses: notchcast-core-test, nc-Clock-model-test"

    def test_pushes_head_plainly_then_dispatches_once_without_looking_for_a_push_run(self):
        self.commit("two")
        self.head = self.rev(self.repo, "HEAD")
        self.scenario(view=self.view("success"))
        result = self.ci()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], self.passed())
        self.assertEqual(self.rev(self.origin, "refs/heads/feat"), self.head)
        self.assertEqual(self.rev(self.repo, "feat@{upstream}"), self.head)
        calls = self.calls()
        self.assertFalse([c for c in calls if c[:2] == ["run", "list"]])
        self.assertEqual(len([c for c in calls if "-X" in c]), 1)

    def test_no_push_dispatches_without_pushing(self):
        self.git(self.repo, "remote", "set-url", "--push", "origin", str(Path(self.tmp.name) / "missing.git"))
        result = self.ci("--no-push")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], self.passed())
        self.assertEqual(len([c for c in self.calls() if "-X" in c]), 1)

    def test_a_rejected_push_stops_before_any_gh_call(self):
        other = Path(self.tmp.name) / "other"
        self.git(Path(self.tmp.name), "clone", "-q", "-b", "feat", str(self.origin), str(other))
        (other / "elsewhere").write_text("x")
        self.git(other, "add", "elsewhere")
        self.git(other, "commit", "-qm", "elsewhere")
        self.git(other, "push", "-q", "origin", "feat")
        self.commit("two")
        result = self.ci()
        self.assertEqual(result.returncode, 2)
        self.assertIn("git push origin HEAD:refs/heads/feat failed", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_pass_lists_the_changed_harnesses_and_watches_the_dispatched_run(self):
        result = self.ci()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], self.passed())
        calls = self.calls()
        dispatch = next(c for c in calls if "-X" in c)
        self.assertIn("repos/Kaczor-Labs/notchcast/actions/workflows/main-harnesses.yml/dispatches", dispatch)
        self.assertIn("ref=feat", dispatch)
        self.assertEqual(self.views(), [["run", "view", "777", "-R", "Kaczor-Labs/notchcast", "--json",
                                  "status,conclusion,headSha"]])
        self.assertFalse([c for c in calls if c[:2] == ["run", "watch"]])
        self.assertFalse([c for c in calls if c[:2] == ["run", "list"]])

    def test_polls_the_dispatched_run_until_it_completes(self):
        self.scenario(view=[self.view(None, status="queued"), self.view(None, status="in_progress"),
                            self.view("success")])
        result = self.ci()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.splitlines()[-1].startswith(f"PASS {URL} "))
        self.assertEqual(len(self.views()), 3)

    def test_rate_limit_waits_for_the_reset_then_carries_on(self):
        self.scenario(limited={"poll": 2, "view": 1})
        result = self.ci()
        self.assertEqual(result.returncode, 0, result.stderr)
        waits = [line for line in result.stdout.splitlines() if "rate limit" in line]
        self.assertEqual(len(waits), 3)
        for line in waits:
            self.assertRegex(line, r"^notchcast-ci: GitHub API rate limit; waiting until \d\d:\d\d UTC$")
        calls = self.calls()
        self.assertEqual(len([c for c in calls if c[-1] == ".resources.core.reset"]), 3)
        self.assertEqual(len(self.views()), 2)
        self.assertTrue(result.stdout.splitlines()[-1].startswith(f"PASS {URL} "))

    def test_a_low_api_budget_waits_for_the_reset_before_dispatching(self):
        self.scenario(remaining=[120, 499, 4800])
        result = self.ci()
        self.assertEqual(result.returncode, 0, result.stderr)
        waits = [line for line in result.stdout.splitlines() if "API calls left" in line]
        self.assertEqual(len(waits), 2)
        self.assertRegex(waits[0], r"^notchcast-ci: 120 API calls left \(<500\); waiting until \d\d:\d\d UTC$")
        self.assertTrue(waits[1].startswith("notchcast-ci: 499 API calls left (<500); waiting until "))
        calls = self.calls()
        budget = [i for i, c in enumerate(calls) if c[-1] == ".resources.core.remaining"]
        self.assertEqual(len(budget), 3)
        self.assertLess(budget[-1], next(i for i, c in enumerate(calls) if "-X" in c))
        self.assertTrue(result.stdout.splitlines()[-1].startswith(f"PASS {URL} "))

    def test_fail_prints_the_failed_log_tail_then_the_verdict(self):
        self.scenario(view=self.view("failure"),
                      log_failed="\n".join(f"failed line {n}" for n in range(1, 61)))
        result = self.ci()
        lines = result.stdout.splitlines()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(lines[-1], f"FAIL {URL} at {self.head[:12]} harnesses: notchcast-core-test, nc-Clock-model-test")
        self.assertEqual(lines[-41:-1], [f"failed line {n}" for n in range(21, 61)])
        self.assertNotIn("failed line 20", result.stdout)

    def test_no_harness_selected_says_so(self):
        self.scenario(log="\n".join([log_line("##[group]Run x"), log_line("fi"), log_line("##[endgroup]")]))
        result = self.ci()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines()[-1], f"PASS (no harnesses selected) {URL} at {self.head[:12]}")

    def test_finds_the_step_by_its_script_when_gh_labels_every_line_unknown_step(self):
        unknown = "UNKNOWN STEP"
        self.scenario(log="\n".join([
            log_line("##[group]Run actions/checkout@v5", step=unknown), log_line("##[endgroup]", step=unknown),
            log_line("checkout-output", step=unknown),
            log_line("##[group]Run git fetch -q origin", step=unknown),
            log_line("\x1b[36;1m./notchcast/changed-harnesses.sh \"$BEFORE\" \"$GITHUB_SHA\"\x1b[0m", step=unknown),
            log_line("##[endgroup]", step=unknown),
            log_line("nc-Clock-model-test", step=unknown),
            log_line("##[group]Run echo done", step=unknown), log_line("##[endgroup]", step=unknown),
            log_line("not-a-harness", step=unknown),
            f"harnesses (0)\t{unknown}\t2026-11-09T10:05:00.1Z other-job-line",
        ]))
        result = self.ci()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines()[-1], f"PASS {URL} at {self.head[:12]} harnesses: nc-Clock-model-test")

    def test_a_log_without_the_step_or_no_readable_log_is_unknown_not_none_selected_or_an_error(self):
        for log in (log_line("##[group]Run something else", step="UNKNOWN STEP"), None):
            with self.subTest(log=log):
                self.scenario(log=log)
                result = self.ci()
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout.splitlines()[-1], f"PASS {URL} at {self.head[:12]} harnesses: unknown")

    def test_without_keeper_it_refuses_before_pushing_or_calling_gh(self):
        self.commit("two")
        for args in ((), ("--no-push",), ("--run", "777")):
            with self.subTest(args=args):
                result = self.ci(*args, keeper=())
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "Main harnesses is Keeper-only: push your branch (git push) and ask "
                                                "your Keeper for the harness proof\n")
                self.assertEqual(self.calls(), [])
                self.assertNotEqual(self.rev(self.origin, "refs/heads/feat"), self.rev(self.repo, "HEAD"))

    def test_a_run_that_has_not_started_blocks_the_dispatch(self):
        for status in ("queued", "pending", "waiting", "requested"):
            with self.subTest(status=status):
                (self.fake / "calls.log").unlink(missing_ok=True)
                self.scenario(polls=[[run_state(1, "in_progress"), run_state(2, status), run_state(20, "completed")]])
                result = self.ci()
                self.assertEqual(result.returncode, 4, result.stderr)
                self.assertEqual(result.stdout.splitlines()[-1], "QUEUED https://example.test/runs/2: one Main "
                                 "harnesses run already waits; rerun when it starts")
                self.assertFalse([c for c in self.calls() if "-X" in c or c[:2] == ["run", "view"]])

    def test_runs_in_progress_other_workflows_and_push_events_do_not_block_the_dispatch(self):
        others = [run_state(10, "queued", workflow="pr.yml", event="pull_request"),
                  run_state(11, "queued", workflow="sync.yml", event="workflow_dispatch"),
                  run_state(12, "queued", event="push")]
        for runs in ([run_state(1, "in_progress"), *others, run_state(20, "completed")], []):
            with self.subTest(runs=len(runs)):
                (self.fake / "calls.log").unlink(missing_ok=True)
                self.scenario(polls=[runs])
                result = self.ci()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines()[-1], self.passed())
                calls = self.calls()
                polls = [i for i, c in enumerate(calls) if any("/runs?" in a for a in c)]
                self.assertEqual([calls[i] for i in polls], [["api", "repos/Kaczor-Labs/notchcast/actions/workflows/"
                                                              "main-harnesses.yml/runs?event=workflow_dispatch&per_page=50"]])
                self.assertEqual([i > polls[0] for i, c in enumerate(calls) if "-X" in c], [True])

    def test_a_dispatch_response_without_a_run_id_is_an_error(self):
        for response in ({"html_url": URL}, None):
            with self.subTest(response=response):
                (self.fake / "calls.log").unlink(missing_ok=True)
                self.scenario(dispatch=response)
                result = self.ci()
                self.assertEqual(result.returncode, 2)
                self.assertIn("no workflow_run_id", result.stderr)
                self.assertFalse([c for c in self.calls() if c[:2] == ["run", "view"]])

    def test_a_cancelled_run_is_no_proof(self):
        for conclusion in ("cancelled", "timed_out", "skipped"):
            with self.subTest(conclusion=conclusion):
                (self.fake / "calls.log").unlink(missing_ok=True)
                self.scenario(view=self.view(conclusion))
                result = self.ci()
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout.splitlines()[-1], f"NOPROOF {URL} conclusion {conclusion}; rerun")
                self.assertFalse([c for c in self.calls() if "--log-failed" in c])

    def test_a_run_of_another_sha_says_the_branch_moved(self):
        other = "f" * 40
        self.scenario(view=self.view("success", sha=other))
        result = self.ci()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout.splitlines()[-1], self.passed(sha=other))
        self.assertIn("branch moved", result.stderr)

    def test_no_push_refuses_when_origin_is_not_head(self):
        self.commit("two")
        result = self.ci("--no-push")
        self.assertEqual(result.returncode, 2)
        self.assertIn("--no-push: origin/feat is", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertNotEqual(self.rev(self.origin, "refs/heads/feat"), self.rev(self.repo, "HEAD"))

    def test_no_push_refuses_a_branch_origin_lacks(self):
        self.git(self.repo, "checkout", "-q", "-b", "local-only")
        result = self.ci("--no-push")
        self.assertEqual(result.returncode, 2)
        self.assertIn("origin/local-only is missing", result.stderr)

    def test_a_tracked_python_cache_is_refused_before_any_push(self):
        for path in ("notchcast/__pycache__/x.cpython-315.pyc", "tool.pyc", "a/__pycache__/README"):
            with self.subTest(path=path):
                self.git(self.repo, "checkout", "-q", "-B", "cache", "feat")
                (self.repo / path).parent.mkdir(parents=True, exist_ok=True)
                (self.repo / path).write_text("")
                self.git(self.repo, "add", "-f", path)
                self.git(self.repo, "commit", "-qm", "cache")
                result = self.ci()
                self.assertEqual(result.returncode, 2)
                self.assertIn(f"HEAD tracks Python caches ({path})", result.stderr)
                self.assertEqual(self.calls(), [])
                self.assertEqual(subprocess.run(["git", "-C", str(self.origin), "rev-parse", "-q", "--verify",
                                                 "refs/heads/cache"], capture_output=True).returncode, 1)

    def test_a_clone_without_the_repo_hooks_is_refused_before_any_push(self):
        self.commit("two")
        for value in (None, ".git/hooks", "notchcast/githooks"):
            with self.subTest(hooks=value):
                if value is None:
                    self.git(self.repo, "config", "--unset", "core.hooksPath")
                else:
                    self.git(self.repo, "config", "core.hooksPath", value)
                result = self.ci()
                self.assertEqual(result.returncode, 2)
                self.assertIn(f"core.hooksPath is {value or 'unset'}", result.stderr)
                self.assertEqual(self.calls(), [])
                self.assertNotEqual(self.rev(self.origin, "refs/heads/feat"), self.rev(self.repo, "HEAD"))

    def test_the_configured_hooks_directory_must_contain_an_executable_pre_push(self):
        (self.hooks / "pre-push").chmod(0o644)
        result = self.ci()
        self.assertEqual(result.returncode, 2)
        self.assertIn("pre-push is missing or not executable", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_main_and_detached_head_are_refused(self):
        self.git(self.repo, "checkout", "-q", "--detach")
        self.assertEqual(self.ci().returncode, 2)
        self.git(self.repo, "checkout", "-q", "-b", "main")
        self.assertEqual(self.ci().returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_max_wait_after_dispatch_prints_pending_with_the_run_to_resume(self):
        self.scenario(view=self.view(None, status="in_progress"))
        result = self.ci("--max-wait", "20", NOTCHCAST_CI_POLL="1")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], f"PENDING {URL} at {self.head[:12]}; rerun: {self.rerun()} --run 777")
        self.assertEqual(len([c for c in self.calls() if "-X" in c]), 1)

    def test_a_hanging_gh_call_ends_within_max_wait(self):
        pending = f"PENDING {URL} at {self.head[:12]}; rerun: {self.rerun()} --run 777"
        waiting = f"WAITING (not dispatched); rerun: {self.rerun()} --no-push"
        for hang, last in (("--json status", pending), ("--log", pending), ("event=workflow_dispatch", waiting)):
            with self.subTest(hang=hang):
                self.scenario(hang=[hang])
                # real time: subprocess.run's own timeout cuts the hung call, 1 s per subtest; no other call is timed
                result = subprocess.run([sys.executable, "-c", TIME_ONLY_THE_HUNG_CALL, hang, str(CI), "--repo",
                                         str(self.repo), "--keeper", "--max-wait", "1"], text=True, capture_output=True, env=self.env)
                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertEqual(result.stdout.splitlines()[-1], last)

    def test_run_polls_that_run_without_pushing_or_dispatching(self):
        self.scenario(view=[self.view(None, status="in_progress"), self.view("success")])
        result = self.ci("--run", "777")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], self.passed())
        calls = self.calls()
        self.assertFalse([c for c in calls if "-X" in c or any("/runs?" in a for a in c) or c[:2] == ["run", "list"]])
        self.assertEqual(len(self.views()), 2)
        self.assertIn(["api", "repos/Kaczor-Labs/notchcast/actions/runs/777", "--jq", ".path"], calls)

    def test_run_of_another_workflow_proves_nothing(self):
        for path in (".github/workflows/build.yml", ".github/workflows/main-harnesses.yml.bak", ""):
            with self.subTest(path=path):
                self.scenario(run_path=path, view=self.view("success"))
                result = self.ci("--run", "777")
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertNotIn("PASS", result.stdout)
                self.assertIn("not main-harnesses.yml", result.stderr)

    def test_help_works(self):
        result = subprocess.run([sys.executable, str(CI), "--help"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("--keeper", result.stdout)


if __name__ == "__main__":
    unittest.main()
