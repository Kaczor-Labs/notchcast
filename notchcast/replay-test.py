#!/usr/bin/env python3
"""Exercise replay's catalog resolution and conflict boundaries in isolated repositories."""
import importlib.util
import json
import re
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
CATALOG = "Tinycast/Resources/Localizable.xcstrings"


class RebaseHoldTests(unittest.TestCase):
    PR = {"number": 411, "isDraft": False, "isCrossRepository": False}

    def test_open_pr_holds_rebase(self):
        self.assertEqual(CI.rebase_hold([self.PR], 0, 8.8 * 3600),
                         (True, "open PRs #411; 3.2 h of 12 left"))

    def test_expired_hold_allows_rebase_with_warning(self):
        for hours in (12, 13):
            with self.subTest(hours=hours):
                self.assertEqual(CI.rebase_hold([self.PR], 0, hours * 3600),
                                 (False, "::warning::main: 12-hour hold expired with PRs #411 still open"))

    def test_no_open_pr_allows_rebase(self):
        self.assertEqual(CI.rebase_hold([], 0, 3600), (False, ""))

    def test_drafts_and_cross_repository_prs_do_not_hold(self):
        self.assertEqual(CI.rebase_hold([dict(self.PR, isDraft=True),
                                        dict(self.PR, isCrossRepository=True)], 0, 3600), (False, ""))

    def test_message_names_all_eligible_prs(self):
        self.assertEqual(CI.rebase_hold([dict(self.PR, number=412), self.PR], 0, 0),
                         (True, "open PRs #411, #412; 12.0 h of 12 left"))


class SyncWorkflowTests(unittest.TestCase):
    def job(self, name):
        text = (Path(__file__).resolve().parent.parent / ".github/workflows/sync.yml").read_text().split("\njobs:\n")[1]
        match = re.search(rf"^  {name}:\n(.*?)(?=^  \S|\Z)", text, re.M | re.S)
        self.assertIsNotNone(match, name)
        return match[1]

    def test_release_failure_never_skips_main(self):
        """Releases run after main and from plan's main; main depends on plan alone, never on a release."""
        self.assertRegex(self.job("main"), r"(?m)^    needs: plan$")
        self.assertNotIn("release", re.search(r"(?m)^    if: (.*)$", self.job("main"))[1])
        self.assertRegex(self.job("release"), r"(?m)^    needs: \[plan, main, push\]$")


    def test_main_only_moves_forward(self):
        """Pushing main is a plain push: no --force and no lease; ci.py forward checks it first."""
        self.assertIn('ci.py merge . "${{ needs.plan.outputs.main }}" "$UP"', self.job("main"))
        push = self.job("push")
        self.assertIn('ci.py forward "$OLD" "$HEAD_SHA"', push)
        self.assertNotRegex(push, r"push[^\n]*(--force|\s-f\s|\+\S*refs/heads/main)")


class SyncMergeTests(unittest.TestCase):
    """Two syncs in a row: main gains a merge each time, keeps every commit, and still replays."""

    def test_two_syncs_keep_main_history_and_our_commits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def commit(path, text, message):
                (root / path).write_text(text)
                git("add", path)
                git("commit", "-qm", message)
                return git("rev-parse", "HEAD")
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            base = commit("upstream", "1\n", "upstream 1")
            first = commit("ours", "first\n", "Notchcast: first")
            git("checkout", "-q", "--detach", base)
            upstream = commit("upstream", "2\n", "upstream 2")
            main = first
            for round, ours in ((1, None), (2, "Notchcast: second")):
                git("checkout", "-q", "--detach", main)
                if ours:
                    main = commit("ours", "first\nsecond\n", ours)
                if round == 2:
                    git("checkout", "-q", "--detach", upstream)
                    upstream = commit("upstream", "3\n", "upstream 3")
                    git("checkout", "-q", "--detach", main)
                git("update-ref", "refs/remotes/upstream/main", upstream)
                CI.replay(root, upstream, check=True)
                CI.merge(root, main, upstream)
                merged = git("rev-parse", "HEAD")
                self.assertEqual(git("rev-parse", "HEAD^1", "HEAD^2").split(), [main, upstream])
                self.assertTrue(git("show", "-s", "--format=%s", merged).startswith(CI.SYNC_MERGE))
                CI.forward(main, merged, cwd=root)
                main = merged
            self.assertEqual((root / "upstream").read_text(), "3\n")
            self.assertEqual((root / "ours").read_text(), "first\nsecond\n")
            self.assertEqual(git("merge-base", "--is-ancestor", first, main), "")
            self.assertEqual(len(git("rev-list", "--merges", main).split()), 2)
            self.assertIsNone(CI.upstream_dropped(main, upstream, cwd=root))
            git("checkout", "-q", "--detach", base)
            rewritten = commit("upstream", "rewritten\n", "upstream rewritten")
            self.assertEqual(CI.upstream_dropped(main, rewritten, cwd=root), upstream)
            with self.assertRaises(SystemExit) as caught:
                CI.merge(root, main, rewritten)
            self.assertIn("upstream rewrote its history", str(caught.exception.code))

    def test_forward_refuses_a_rewrite_and_names_the_way_through(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("commit", "-q", "--allow-empty", "-m", "base")
            git("commit", "-q", "--allow-empty", "-m", "main")
            main = git("rev-parse", "HEAD")
            git("commit", "-q", "--amend", "--allow-empty", "-m", "replayed main")
            rewritten = git("rev-parse", "HEAD")
            CI.forward(main, main, cwd=root)
            with self.assertRaises(SystemExit) as caught:
                CI.forward(main, rewritten, cwd=root)
            message = str(caught.exception.code)
            self.assertIn("rewrites main's history", message)
            self.assertIn("ci.py merge", message)
            self.assertIn("Never force-push main", message)

    def test_a_merge_that_is_no_sync_merge_stops_the_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("commit", "-q", "--allow-empty", "-m", "upstream")
            upstream = git("rev-parse", "HEAD")
            git("commit", "-q", "--allow-empty", "-m", "side")
            side = git("rev-parse", "HEAD")
            git("checkout", "-q", "--detach", upstream)
            git("commit", "-q", "--allow-empty", "-m", "ours")
            git("merge", "-q", "--no-ff", "-m", "Merge branch side", side)
            git("update-ref", "refs/remotes/upstream/main", upstream)
            with self.assertRaises(SystemExit) as caught:
                CI.replay(root, upstream, check=True)
            self.assertIn("no sync merge", str(caught.exception.code))


class AppInfoTests(unittest.TestCase):
    INFO = {"CFBundleName": "Tinycast", "CFBundleIdentifier": "com.tinycast.app.beta",
            "CFBundleShortVersionString": "0.12.10-beta.135", "CFBundleVersion": "135"}

    def test_upstream_values_pass_whole(self):
        self.assertEqual(CI.app_info_outputs(self.INFO), {"name": "Tinycast", "bundle_id": "com.tinycast.app.beta",
                                                          "version": "0.12.10-beta.135", "build": "135"})

    def test_a_value_that_could_add_an_output_line_is_refused(self):
        for key, value in (("CFBundleVersion", "135\nversion=9.9.9"), ("CFBundleName", "Tiny\ncast"),
                           ("CFBundleIdentifier", "com.x;y"), ("CFBundleShortVersionString", "1.0"),
                           ("CFBundleVersion", None)):
            with self.subTest(key=key), self.assertRaises(SystemExit):
                CI.app_info_outputs(dict(self.INFO, **{key: value}))


class TestedKeyTests(unittest.TestCase):
    def test_key_ignores_regenerated_files_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def commit(files):
                for name, text in files.items():
                    (root / name).parent.mkdir(parents=True, exist_ok=True)
                    (root / name).write_text(text)
                git("add", ".")
                git("commit", "-qm", "c")
                return git("rev-parse", "HEAD")
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            plain = commit({"code": "one\n"})
            regenerated = [CI.PBXPROJ, CI.SCHEME, "README.md"]
            generated = commit({name: "regenerated\n" for name in regenerated})
            again = commit({name: "regenerated again\n" for name in regenerated})
            runtime = commit({CI.RUNTIME_JS: "rebuilt\n"})
            changed = commit({"code": "two\n"})
            self.assertEqual(CI.tested_key(plain, root), CI.tested_key(generated, root))
            self.assertEqual(CI.tested_key(generated, root), CI.tested_key(again, root))
            self.assertEqual(CI.tested_key(plain, root), git("rev-parse", f"{plain}^{{tree}}"))
            self.assertNotEqual(CI.tested_key(again, root), CI.tested_key(runtime, root))
            self.assertNotEqual(CI.tested_key(runtime, root), CI.tested_key(changed, root))
            self.assertEqual(git("diff", "--cached", "--name-only"), "")

    RUNS = {1: {"name": "PR", "path": ".github/workflows/pr.yml", "conclusion": "success", "repository": {"id": 5}, "head_repository": {"id": 5, "full_name": "Fork/Repo"}, "html_url": "run-1"}}

    def match(self, artifact, run=None):
        runs = {7: dict(self.RUNS[1], **(run or {}))}
        return CI.tested_run([dict({"workflow_run": {"id": 7}}, **artifact)], runs.__getitem__)

    def test_green_pr_run_of_our_repo_matches(self):
        self.assertEqual(self.match({})["html_url"], "run-1")

    def test_our_repo_matches_after_a_transfer_renamed_it(self):
        self.assertEqual(self.match({}, {"head_repository": {"id": 5, "full_name": "Org/Repo"}})["html_url"], "run-1")

    def test_every_other_run_is_rejected(self):
        for artifact, run in [({"expired": True}, None), ({}, {"conclusion": "failure"}), ({}, {"conclusion": None}),
                              ({}, {"name": "Sync"}), ({}, {"path": ".github/workflows/other.yml"}),
                              ({}, {"head_repository": {"id": 9, "full_name": "someone/repo"}}),
                              ({}, {"repository": None}),
                              ({}, {"head_repository": None})]:
            with self.subTest(artifact=artifact, run=run):
                self.assertIsNone(self.match(artifact, run))

    def test_first_acceptable_artifact_wins_and_none_matches_nothing(self):
        artifacts = [{"expired": True, "workflow_run": {"id": 1}}, {"workflow_run": {"id": 1}}]
        self.assertEqual(CI.tested_run(artifacts, self.RUNS.__getitem__)["html_url"], "run-1")
        self.assertIsNone(CI.tested_run([], self.RUNS.__getitem__))

    CFG = {"FORK_REPO": "fork/repo", "TESTED_CONTEXT": "ctx"}

    def reuse(self, responses, close_error=None):
        calls = []
        def fake(*cmd, **kwargs):
            calls.append(cmd)
            response = responses(cmd)
            if isinstance(response, Exception):
                raise response
            return response
        closer = mock.Mock(side_effect=close_error)
        with (mock.patch.object(CI, "tested_key", return_value="k" * 40), mock.patch.object(CI, "run", fake),
              mock.patch.object(CI, "issue_close", closer)):
            return CI.reuse_pr_build("main-sha", self.CFG), calls, closer

    @staticmethod
    def api(artifacts, run):
        def respond(cmd):
            path = cmd[-1] if cmd[2] != "-X" else None
            if path and "/artifacts?" in path:
                assert f"name=tested-tree-{'k' * 40}" in path
                return json.dumps({"artifacts": artifacts})
            return json.dumps(run) if path else ""
        return respond

    def test_match_posts_the_tested_status_with_the_run_url_and_closes_the_main_issue(self):
        found, calls, closer = self.reuse(self.api([{"workflow_run": {"id": 1}}], self.RUNS[1]))
        self.assertEqual(found["html_url"], "run-1")
        posted = calls[-1]
        self.assertEqual(posted[:4], ("gh", "api", "-X", "POST"))
        self.assertIn("repos/fork/repo/statuses/main-sha", posted)
        for part in ("state=success", "context=ctx", "target_url=run-1"):
            self.assertIn(part, posted)
        closer.assert_called_once_with("main")

    def test_failing_issue_close_keeps_the_reuse(self):
        found, _, closer = self.reuse(self.api([{"workflow_run": {"id": 1}}], self.RUNS[1]),
                                      close_error=subprocess.CalledProcessError(1, "gh"))
        self.assertEqual(found["html_url"], "run-1")
        closer.assert_called_once_with("main")

    def test_no_artifact_or_api_error_posts_nothing(self):
        for responses in (self.api([], {}), lambda cmd: subprocess.CalledProcessError(1, cmd),
                          lambda cmd: "not json", lambda cmd: json.dumps({})):
            with self.subTest(responses=responses):
                found, calls, closer = self.reuse(responses)
                self.assertIsNone(found)
                self.assertFalse([c for c in calls if "POST" in c])
                closer.assert_not_called()

    def test_failing_status_post_means_no_reuse(self):
        base = self.api([{"workflow_run": {"id": 1}}], self.RUNS[1])
        found, _, closer = self.reuse(lambda cmd: subprocess.CalledProcessError(1, cmd) if "POST" in cmd else base(cmd))
        self.assertIsNone(found)
        closer.assert_not_called()


class ReplayTests(unittest.TestCase):
    def scenario(self, column_zero=False, conflict=None, later_conflict=False, fix=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def catalog(entries):
                text = json.dumps({"sourceLanguage": "en", "strings": entries, "version": "1.0"}, indent=2) + "\n"
                if column_zero:
                    text = text.replace('    "', '"')
                path = root / CATALOG
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            def commit(message):
                git("add", ".")
                git("commit", "-qm", message)
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            catalog({"a": {}, "z": {}})
            (root / "other").write_text("base\n")
            (root / "second").write_text("base\n")
            commit("base")
            base = git("rev-parse", "HEAD")
            catalog({"a": {}, "ours": {}, "z": {}})
            if conflict == "other":
                (root / "other").write_text("ours\n")
                if fix == "partial":
                    (root / "second").write_text("ours\n")
            commit("ours")
            (root / "clean").write_text("clean cherry-pick result\n")
            git("add", "clean")
            git("commit", "--amend", "--no-edit", "-q")
            if later_conflict:
                (root / "other").write_text("ours\n")
                commit("later conflict")
            ours = git("rev-parse", "HEAD")
            git("checkout", "-q", "--detach", base)
            entries = {"a": {}, "upstream": {}, "z": {}}
            if conflict == "catalog":
                entries["ours"] = {"comment": "different"}
            if conflict == "deleted catalog":
                git("rm", CATALOG)
            else:
                catalog(entries)
            (root / "other").write_text("upstream\n")
            (root / "second").write_text("upstream\n")
            commit("upstream")
            upstream = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/upstream/main", upstream)
            git("checkout", "-q", "--detach", ours)
            if fix:
                path = root / "notchcast/replay-fixes/ours.patch"
                path.parent.mkdir(parents=True)
                valid = "diff --git a/other b/other\n--- a/other\n+++ b/other\n@@ -1 +1,2 @@\n upstream\n+ours\n"
                if fix == "labelled":
                    # A fix for another base first, then the one for this base under a label.
                    path.write_text(valid.replace(" upstream\n", " newer upstream\n"))
                    path.with_name("ours.v1-0-0-beta-1.patch").write_text(valid)
                    path.with_name("ours-longer.v1.patch").write_text("invalid patch\n")
                else:
                    path.write_text(valid if fix in {"valid", "partial", "extra"} else "invalid patch\n")
                if fix == "extra":
                    with path.open("a") as stream:
                        stream.write("diff --git a/clean b/clean\n--- a/clean\n+++ b/clean\n"
                                     "@@ -1 +1 @@\n-clean cherry-pick result\n+changed\n")
                commit("stored fix")
            if (conflict or later_conflict) and fix not in {"valid", "labelled"}:
                with self.assertRaises(CI.Conflict) as caught:
                    CI.replay(root, upstream, check=True)
                self.assertEqual(caught.exception.subject, "later conflict" if later_conflict else "ours")
                self.assertEqual(caught.exception.files,
                                 ["other", "second"] if fix == "partial" else
                                 ["other"] if later_conflict or conflict == "other" else [CATALOG])
            else:
                CI.replay(root, upstream, check=True)
                self.assertEqual(set(json.loads((root / CATALOG).read_text())["strings"]),
                                 {"a", "ours", "upstream", "z"})
                self.assertEqual(git("diff", "--name-only", "--diff-filter=U"), "")
                self.assertEqual((root / "clean").read_text(), "clean cherry-pick result\n")
                if fix in {"valid", "labelled"}:
                    self.assertEqual((root / "other").read_text(), "upstream\nours\n")

    def test_per_file_fix_preserves_clean_results_and_catalog(self):
        self.scenario(conflict="other", fix="valid")

    def test_fix_labelled_for_another_base_applies_when_the_bare_fix_does_not(self):
        self.scenario(conflict="other", fix="labelled")

    def test_invalid_fix_raises_conflict(self):
        self.scenario(conflict="other", fix="invalid")

    def test_fix_missing_conflicting_file_raises_conflict(self):
        self.scenario(conflict="other", fix="partial")

    def test_fix_touching_clean_file_raises_conflict(self):
        self.scenario(conflict="other", fix="extra")

    def test_adjacent_additions(self):
        self.scenario()

    def test_column_zero(self):
        self.scenario(column_zero=True)

    def test_value_conflict(self):
        self.scenario(conflict="catalog")

    def test_upstream_deletes_catalog(self):
        self.scenario(conflict="deleted catalog")

    def test_other_conflict(self):
        self.scenario(conflict="other")

    def test_resolution_does_not_mask_later_failure(self):
        self.scenario(later_conflict=True)

    def deletion(self, fix):
        """Upstream deletes a file our commit edits; the stored fix takes the deletion, or not."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def commit(message, files, removed=()):
                for name, text in files.items():
                    (root / name).parent.mkdir(parents=True, exist_ok=True)
                    (root / name).write_text(text)
                for name in removed:
                    git("rm", "-q", name)
                git("add", ".")
                git("commit", "-qm", message)
                return git("rev-parse", "HEAD")
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            base = commit("base", {"chip": "base\n", "keep": "base\n"})
            ours = commit("ours", {"chip": "ours\n", "keep": "ours\n"})
            git("checkout", "-q", "--detach", base)
            upstream = commit("upstream", {}, removed=["chip"])
            git("update-ref", "refs/remotes/upstream/main", upstream)
            git("checkout", "-q", "--detach", ours)
            commit("stored fix", {"notchcast/replay-fixes/ours.patch": fix})
            if fix.startswith("diff"):
                CI.replay(root, upstream, check=True)
                self.assertFalse((root / "chip").exists())
                self.assertEqual((root / "keep").read_text(), "ours\n")
            else:
                with self.assertRaises(CI.Conflict) as caught:
                    CI.replay(root, upstream, check=True)
                self.assertEqual(caught.exception.files, ["chip"])

    def test_fix_takes_upstream_deletion(self):
        self.deletion("diff --git a/chip b/chip\ndeleted file mode 100644\n--- a/chip\n+++ /dev/null\n"
                      "@@ -1 +0,0 @@\n-ours\n")

    def test_deletion_without_fix_raises_conflict(self):
        self.deletion("invalid patch\n")

    def adaptation(self, patch, adapted=None, path="scope"):
        """Our commit adds a key and picks cleanly; upstream adds a list of every key that lacks it, which no
        conflict reveals. The stored adaptation for our commit adds it there."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def commit(message, files):
                for name, text in files.items():
                    (root / name).parent.mkdir(parents=True, exist_ok=True)
                    (root / name).write_text(text)
                git("add", ".")
                git("commit", "-qm", message)
                return git("rev-parse", "HEAD")
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            base = commit("base", {"keys": "a\n"})
            commit("Ours: add a key", {"keys": "a\nours\n", **({path: adapted} if adapted else {})})
            if patch:
                commit("stored adaptation", {f"{CI.ADAPTATIONS}/{name}": text for name, text in patch.items()})
            ours = git("rev-parse", "HEAD")
            git("checkout", "-q", "--detach", base)
            upstream = commit("upstream", {"scope": "a\n"} if not adapted else {"other": "x\n"})
            git("update-ref", "refs/remotes/upstream/main", upstream)
            git("checkout", "-q", "--detach", ours)
            CI.replay(root, upstream, check=True)
            return ((root / path).read_text(), git("show", "--format=", "--name-only", "HEAD~1"),
                    git("status", "--porcelain"))

    ADAPT = "diff --git a/scope b/scope\n--- a/scope\n+++ b/scope\n@@ -1 +1,2 @@\n a\n+ours\n"

    def test_adaptation_applies_after_a_clean_pick(self):
        self.assertEqual(self.adaptation({"ours-add-a-key.patch": self.ADAPT}), ("a\nours\n", "keys\nscope", ""))

    def test_adaptation_labelled_for_another_base_applies_when_the_bare_one_does_not(self):
        scope, _, _ = self.adaptation({"ours-add-a-key.patch": self.ADAPT.replace(" a\n", " b\n"),
                                       "ours-add-a-key.v1-0-0.patch": self.ADAPT})
        self.assertEqual(scope, "a\nours\n")

    def test_adaptation_that_does_not_apply_fails_on_its_commit(self):
        with self.assertRaises(CI.Conflict) as caught:
            self.adaptation({"ours-add-a-key.patch": self.ADAPT.replace(" a\n", " b\n")})
        self.assertEqual((caught.exception.subject, caught.exception.files), ("Ours: add a key", ["scope"]))

    def test_adaptation_already_in_the_commit_counts_as_applied(self):
        """After Sync rewrote main, our commit carries the adapted lines; a stale adaptation must not block."""
        self.assertEqual(self.adaptation({"ours-add-a-key.patch": self.ADAPT}, adapted="a\nours\n")[0], "a\nours\n")

    def test_adaptation_in_one_of_two_repeated_contexts_does_not_count_as_applied(self):
        """git's reverse check matches the patched copy and ignores the untouched one; the replay must fail."""
        patch = "diff --git a/scope b/scope\n--- a/scope\n+++ b/scope\n@@ -1,2 +1,3 @@\n foo\n+ours\n bar\n"
        with self.assertRaises(CI.Conflict) as caught:
            self.adaptation({"ours-add-a-key.patch": patch}, adapted="foo\nours\nbar\nfoo\nbar\n")
        self.assertEqual((caught.exception.subject, caught.exception.files), ("Ours: add a key", ["scope"]))

    PAGE = "p1\np2\np3\np4\n"

    def test_adaptation_in_one_of_two_repeated_mid_file_contexts_does_not_count_as_applied(self):
        """A forward apply would patch the second copy at an offset; the replay must fail instead."""
        patch = "diff --git a/scope b/scope\n--- a/scope\n+++ b/scope\n@@ -5,2 +5,3 @@\n foo\n+ours\n bar\n"
        with self.assertRaises(CI.Conflict) as caught:
            self.adaptation({"ours-add-a-key.patch": patch}, adapted=self.PAGE + "foo\nours\nbar\nfoo\nbar\n")
        self.assertEqual((caught.exception.subject, caught.exception.files), ("Ours: add a key", ["scope"]))

    def test_deletion_left_in_one_of_two_copies_does_not_count_as_applied(self):
        """The deletion's new lines are a prefix of its old ones, so they must not hide the unpatched copy."""
        patch = "diff --git a/scope b/scope\n--- a/scope\n+++ b/scope\n@@ -5,3 +5,2 @@\n foo\n bar\n-baz\n"
        with self.assertRaises(CI.Conflict) as caught:
            self.adaptation({"ours-add-a-key.patch": patch}, adapted=self.PAGE + "foo\nbar\nbaz\nfoo\nbar\n")
        self.assertEqual((caught.exception.subject, caught.exception.files), ("Ours: add a key", ["scope"]))

    def test_quoted_patch_path_is_checked_for_unpatched_copies(self):
        """git C-quotes unusual paths and ends a spaced one with a tab; both must reach the file."""
        patch = ('diff --git "a/my file" "b/my file"\n--- "a/my file"\t\n+++ "b/my file"\t\n'
                 "@@ -1,2 +1,3 @@\n foo\n+ours\n bar\n")
        with self.assertRaises(CI.Conflict) as caught:
            self.adaptation({"ours-add-a-key.patch": patch}, adapted="foo\nours\nbar\nfoo\nbar\n", path="my file")
        self.assertEqual((caught.exception.subject, caught.exception.files), ("Ours: add a key", ["my file"]))

    def test_no_adaptation_leaves_the_clean_pick_alone(self):
        scope, _, status = self.adaptation(None)
        self.assertEqual((scope, status), ("a\n", ""))

    def test_pruned_paths_stay_gone_without_conflict(self):
        """Our generated commit removes website/; upstream keeps editing it. The replay never picks that removal,
        so it cannot conflict, and regenerate removes the path again."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return CI.run("git", *args, cwd=root)
            def write(path, text):
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_text(text)
            def commit(message):
                git("add", "-A")
                git("commit", "-qm", message)
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            git("config", "core.hooksPath", "/dev/null")
            write("README.md", "upstream readme\n")
            write("website/page.md", "base\n")
            write("website/package-lock.json", "{}\n")
            write("project.yml", "name: Tinycast\n")
            write(CI.PBXPROJ, "project\n")
            write(CI.SCHEME, "scheme\n")
            write(CI.RUNTIME_JS, "runtime\n")
            write("docs/screenshot.png", "png\n")
            write("docs/development.md", "kept\n")
            write("Scripts/gen-emoji.js", "generator\n")
            write("Scripts/lint.sh", "kept\n")
            commit("base")
            base = git("rev-parse", "HEAD")
            write("notchcast/README.public.md", "ours\n")
            write("notchcast/prune-paths.txt",
                  "# one path per line\n\nwebsite/\ndocs/screenshot.png\nREADME.upstream.md\nScripts/gen-emoji.js\n")
            write("feature.swift", "ours\n")
            write("Tinycast/Features/Notchcast/Core/NotchcastAddon.swift", "protocol NotchcastAddon {}\n")
            write("README.upstream.md", "made by the old regenerate\n")
            commit("ours")
            CI.regenerate(root, base)
            git("add", "-A", "--", *CI.GENERATED)
            git("commit", "-qm", CI.GENERATED_COMMIT)
            self.assertFalse((root / "website").exists())
            self.assertEqual(git("ls-files", "README.upstream.md", "docs/screenshot.png", "Scripts/gen-emoji.js"), "")
            self.assertEqual(git("ls-files", "docs", "Scripts"), "Scripts/lint.sh\ndocs/development.md")
            ours = git("rev-parse", "HEAD")
            git("checkout", "-q", "--detach", base)
            write("website/page.md", "upstream edit\n")
            write("website/new.md", "new page\n")
            commit("upstream edits the website")
            upstream = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/upstream/main", upstream)
            git("checkout", "-q", "--detach", ours)
            CI.replay(root, upstream)
            self.assertEqual(git("log", "-1", "--format=%s"), CI.GENERATED_COMMIT)
            self.assertEqual(git("ls-files", "website"), "")
            self.assertFalse((root / "website").exists())
            self.assertEqual(git("status", "--porcelain"), "")
            self.assertEqual((root / "feature.swift").read_text(), "ours\n")
            self.assertEqual(git("ls-files", "README.upstream.md", "docs/screenshot.png", "Scripts/gen-emoji.js"), "")
            # A second regenerate on the result is a no-op: nothing left to prune.
            CI.regenerate(root, upstream)
            self.assertEqual(git("status", "--porcelain"), "")

    def test_prune_list_never_covers_kept_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "notchcast").mkdir()
            (root / "docs/features").mkdir(parents=True)
            for path in ("LICENSE", "NOTICE.md", "AGENTS.md", "docs/", "docs/features", "docs/ui.md", "Tests/",
                         "Tests/nc-x-test.swift", "Scripts/", "Scripts/raycast-runtime/build.mjs", "/", "."):
                (root / "notchcast/prune-paths.txt").write_text(path + "\n")
                with self.assertRaises(SystemExit, msg=path):
                    CI.pruned(root)
            (root / "notchcast/prune-paths.txt").write_text("docs/screenshot.png\nScripts/gen-emoji.js\n")
            self.assertEqual(CI.pruned(root), ["docs/screenshot.png", "Scripts/gen-emoji.js"])
        # The fork's own list passes.
        CI.pruned(Path(__file__).resolve().parent.parent)


if __name__ == "__main__":
    unittest.main(verbosity=2)
