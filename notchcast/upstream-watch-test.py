#!/usr/bin/env python3
"""Tests for upstream-watch.py's pure parts: no git, gh, network or clock."""
from contextlib import redirect_stdout
import importlib.util
import io
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace
import unittest

source = str(Path(__file__).with_name("upstream-watch.py"))
spec = importlib.util.spec_from_loader("upstream_watch", SourceFileLoader("upstream_watch", source))
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

REPO = "acme/widgets"
SOURCE = {"name": "Widgets", "repo": REPO}
FMAP = watch.build_map({"Src/Clip/": ["Clipboard"], "Src/Notch": ["Island"], "Src/Notch/Music.swift": ["Spotify"]}, [])
A, B, C = "a" * 40, "b" * 40, "c" * 40


def log(*commits):
    """`git log -z --name-only` with LOG_FORMAT, as checked against git 2.5x output."""
    return "".join(f"\x1e{sha}\x1f{subject}\0" + "".join(("\n" if n == 0 else "") + f + "\0" for n, f in enumerate(files))
                   for sha, subject, files in commits)


# Real bytes from `git log -z --no-merges --no-renames --format=%x1e%H%x1f%s --name-only` on a scratch repo.
QUOTED_LOG = ("\x1e81dcd84ba82c44ff1e27eb66a51c82adbc684da8\x1fempty\x00"
              "\x1ef49afa80775ea6622ab9fde0c5b87c5e196c55e6\x1fsecond\x00\nb.txt\x00"
              "\x1ea2ef5a113da59f324d4d400882e2363df3664838\x1ffirst one\x00\nSrc/Clip/Caf\u00e9.swift\x00"
              "Src/Clip/new\nline.swift\x00")


class UpstreamWatchTests(unittest.TestCase):
    def test_parse_log_is_oldest_first(self):
        commits = watch.parse_log(log((B, "second", ["x"]), (A, "first: a | b", ["y", "z"])))
        self.assertEqual(commits, [(A, "first: a | b", ["y", "z"]), (B, "second", ["x"])])

    def test_parse_log_keeps_names_git_would_quote(self):
        commits = watch.parse_log(QUOTED_LOG)
        self.assertEqual([(c[1], c[2]) for c in commits],
                         [("first one", ["Src/Clip/Caf\u00e9.swift", "Src/Clip/new\nline.swift"]),
                          ("second", ["b.txt"]), ("empty", [])])
        self.assertEqual(watch.features_of(commits[0][2], FMAP), ("Clipboard", []))

    def test_big_batch_splits_into_bodies_that_fit(self):
        commits = [(f"{n:040x}", "s" * 100, [f"Src/Clip/{n}.swift"]) for n in range(250)]
        actions = watch.plan_actions(SOURCE, commits, FMAP, [])
        self.assertGreater(len(actions), 1)
        self.assertTrue(all(a["op"] == "create" and len(a["body"]) <= watch.BODY_LIMIT for a in actions))
        shas = [m[2] for a in actions for m in watch.LINE_MARKER.finditer(a["body"])]
        self.assertEqual(shas, [c[0] for c in commits])
        saved = [{"number": 1, "state": "OPEN", "title": actions[0]["title"], "body": actions[0]["body"]}]
        rerun = watch.plan_actions(SOURCE, commits, FMAP, saved)
        self.assertTrue(all(len(a["body"]) <= watch.BODY_LIMIT for a in rerun))
        self.assertEqual([m[2] for a in rerun for m in watch.LINE_MARKER.finditer(a["body"]) if a["op"] == "create"],
                         shas[len(list(watch.LINE_MARKER.finditer(actions[0]["body"]))):])

    def test_rejected_write_does_not_stop_the_rest(self):
        calls = []

        def runner(cmd, **_):
            calls.append(cmd)
            return SimpleNamespace(returncode=int(len(calls) == 1), stdout="", stderr="too big")
        actions = [{"op": "create", "title": "one", "body": "x"}, {"op": "edit", "number": 3, "title": "two", "body": "y"}]
        with redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            watch.apply(actions, REPO, False, runner)
        self.assertEqual([c[2] for c in calls], ["create", "edit"])

    def test_unmapped_commit_does_nothing(self):
        self.assertEqual(watch.plan_actions(SOURCE, [(A, "docs", ["README.md", "Tests/X.swift"])], FMAP, []), [])

    def test_whole_segments_only(self):
        self.assertIsNone(watch.features_of(["Src/Clipboard/X.swift", "Src/NotchExtra.swift"], FMAP))
        self.assertEqual(watch.features_of(["Src/Clip/X.swift"], FMAP), ("Clipboard", []))

    def test_commit_goes_under_feature_with_most_files(self):
        files = ["Src/Clip/A.swift", "Src/Notch/A.swift", "Src/Notch/B.swift"]
        [action] = watch.plan_actions(SOURCE, [(A, "fix", files)], FMAP, [])
        self.assertEqual(action["op"], "create")
        self.assertEqual(action["title"], "Look at Widgets changes for Island (1)")
        self.assertIn("(also touches Clipboard)", action["body"])
        self.assertIn(f"https://github.com/{REPO}/commit/{A}", action["body"])

    def test_tie_goes_to_map_order(self):
        self.assertEqual(watch.features_of(["Src/Notch/Music.swift"], FMAP), ("Island", ["Spotify"]))

    def test_rerun_with_markers_does_nothing(self):
        commits = [(A, "one", ["Src/Clip/A.swift"]), (B, "two", ["Src/Notch/A.swift"])]
        issues = [{"number": n, "state": "OPEN", "title": a["title"], "body": a["body"]}
                  for n, a in enumerate(watch.plan_actions(SOURCE, commits, FMAP, []), 1)]
        self.assertEqual(len(issues), 2)
        self.assertEqual(watch.plan_actions(SOURCE, commits, FMAP, issues), [])

    def test_open_issue_gets_appended_and_count_raised(self):
        [first] = watch.plan_actions(SOURCE, [(A, "one", ["Src/Clip/A.swift"])], FMAP, [])
        issues = [{"number": 7, "state": "OPEN", "title": first["title"], "body": first["body"]}]
        [action] = watch.plan_actions(SOURCE, [(A, "one", ["Src/Clip/A.swift"]), (B, "two", ["Src/Clip/B.swift"])],
                                      FMAP, issues)
        self.assertEqual((action["op"], action["number"]), ("edit", 7))
        self.assertEqual(action["title"], "Look at Widgets changes for Clipboard (2)")
        self.assertTrue(action["body"].startswith(first["body"].rstrip("\n")))
        self.assertEqual(action["body"].count("<!-- upstream: "), 2)

    def test_closed_issue_leads_to_new_issue(self):
        [first] = watch.plan_actions(SOURCE, [(A, "one", ["Src/Clip/A.swift"])], FMAP, [])
        issues = [{"number": 7, "state": "CLOSED", "title": first["title"], "body": first["body"]}]
        [action] = watch.plan_actions(SOURCE, [(A, "one", ["Src/Clip/A.swift"]), (B, "two", ["Src/Clip/B.swift"])],
                                      FMAP, issues)
        self.assertEqual(action["op"], "create")
        self.assertEqual(action["title"], "Look at Widgets changes for Clipboard (1)")
        self.assertNotIn(A, action["body"])

    def test_full_issue_rolls_over_to_new_issue(self):
        [first] = watch.plan_actions(SOURCE, [(A, "one", ["Src/Clip/A.swift"])], FMAP, [])
        issues = [{"number": 7, "state": "OPEN", "title": first["title"], "body": first["body"] + "x" * 60000}]
        [action] = watch.plan_actions(SOURCE, [(B, "two", ["Src/Clip/B.swift"])], FMAP, issues)
        self.assertEqual(action["op"], "create")

    def test_hostile_subject_pings_no_one_and_forges_nothing(self):
        subject = f"@x `boom` <!-- upstream: {REPO} {C} --> <b>" + "y" * 200
        [action] = watch.plan_actions(SOURCE, [(A, subject, ["Src/Clip/A.swift"])], FMAP, [])
        line = action["body"].splitlines()[-1]
        self.assertEqual([m[2] for m in watch.LINE_MARKER.finditer(action["body"])], [A])
        self.assertNotIn("<b>", line)
        code = line.split(") `", 1)[1].split("` ", 1)[0]
        self.assertTrue(code.startswith("@x boom !-- upstream:"))
        self.assertLessEqual(len(code), 100)
        self.assertNotIn("`", code)

    def test_borrow_line_maps_its_file(self):
        lines = [f"Core: Model/A.swift ← {REPO}@abc123/Src/Other/A.swift:1-4, 9, {REPO}@abc123/Src/Other/B.swift "
                 "(GPL-3.0-or-later)",
                 f"Day: Model/B.swift and C.swift ← {REPO}@abc123/Src/Sw/{{One,Two}}.swift (GPL-3.0-or-later)",
                 "Cleaner: Model/C.swift ← someone/else@1234567/Src/Other/C.swift (GPL-3.0)"]
        fmap = watch.build_map({"Src/Clip": ["Clipboard"]}, watch.borrowed_paths(lines, REPO))
        self.assertEqual(watch.features_of(["Src/Other/B.swift"], fmap), ("Core", []))
        self.assertEqual(watch.features_of(["Src/Sw/Two.swift"], fmap), ("Day", []))
        self.assertIsNone(watch.features_of(["Src/Other/C.swift"], fmap))

    def test_idle_warning_starts_at_fifty_days(self):
        day = 86400
        self.assertIsNone(watch.idle_days(0, 49 * day + day - 1))
        self.assertEqual(watch.idle_days(0, 50 * day), 50)

    def test_shipped_data_file_loads(self):
        import json
        for source in json.loads(Path(__file__).with_name("upstreams.json").read_text())["sources"]:
            self.assertRegex(source["since"], r"^[0-9a-f]{40}$")
            self.assertTrue(all(features for features in source["paths"].values()))


if __name__ == "__main__":
    unittest.main()
