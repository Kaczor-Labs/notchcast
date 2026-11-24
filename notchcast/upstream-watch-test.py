#!/usr/bin/env python3
"""Tests for upstream-watch.py's pure parts: no git, gh, network or clock."""
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
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
    return "".join(f"\0{sha}\x1f{subject}\n" + "".join(f + "\n" for f in files) + "\n"
                   for sha, subject, files in commits)


class UpstreamWatchTests(unittest.TestCase):
    def test_parse_log_is_oldest_first(self):
        commits = watch.parse_log(log((B, "second", ["x"]), (A, "first: a | b", ["y", "z"])))
        self.assertEqual(commits, [(A, "first: a | b", ["y", "z"]), (B, "second", ["x"])])

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
