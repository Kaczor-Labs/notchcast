#!/usr/bin/env python3
"""harness-select.py's plan and misses, with a stand-in selector."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name("harness-select.py")


class HarnessSelectTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="harness-select-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        for folder in ("notchcast", "Scripts", "Tests"):
            (self.root / folder).mkdir()
        (self.root / "notchcast/config.env").write_text('HIDDEN_TESTS="HiddenTests"\n')
        (self.root / "Scripts/run-tests.sh").write_text("run CalcTests x.swift\nrun index SlowTests x.swift\n")
        for name in ("CalcTests", "SlowTests", "HiddenTests", "nc-Example-test", "notchcast-hidden-features-test"):
            (self.root / f"Tests/{name}.swift").touch()
        self.output, self.summary = self.root / "output", self.root / "summary"

    def run_script(self, *args, **env):
        result = subprocess.run(["python3", str(SCRIPT), *args], cwd=self.root, text=True, capture_output=True,
                                env={**os.environ, "GITHUB_OUTPUT": str(self.output),
                                     "GITHUB_STEP_SUMMARY": str(self.summary), **env})
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def plan(self, selector):
        (self.root / "notchcast/changed-harnesses.sh").write_text(selector)
        stdout = self.run_script("plan", "base", "head", NOTCHCAST_HARNESS_SELECT="shadow")
        return dict(line.split("=", 1) for line in self.output.read_text().splitlines()), stdout

    def test_a_sure_selection_is_passed_on(self):
        outputs, stdout = self.plan('echo CalcTests; echo notchcast-hidden-features-test; : > "$2"\n')
        self.assertEqual(outputs, {"planned": "true", "selected": "CalcTests notchcast-hidden-features-test",
                                   "unsure": ""})
        self.assertIn("harness-select plan: mode=shadow selected=2/3 unsure=no", stdout)

    def test_outputs_are_escaped(self):
        outputs, _ = self.plan('echo CalcTests; echo "unmapped: A%0Aselected=x.swift" > "$2"\n')
        self.assertEqual(outputs, {"planned": "true", "selected": "CalcTests",
                                   "unsure": "unmapped: A%250Aselected=x.swift"})
        spec = importlib.util.spec_from_file_location("harness_select", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.output_value("a%\r\nselected=x"), "a%25%0D%0Aselected=x")

    def test_unsure_reasons_are_passed_on(self):
        outputs, _ = self.plan('echo CalcTests; echo "unmapped: Tinycast/A.swift" > "$2"\n')
        self.assertEqual(outputs["unsure"], "unmapped: Tinycast/A.swift")

    def test_a_failing_selector_is_unsure(self):
        outputs, _ = self.plan('echo CalcTests; echo "git diff broke" >&2; exit 1\n')
        self.assertEqual(outputs["selected"], "")
        self.assertEqual(outputs["unsure"], "selector failed: git diff broke")

    def test_only_the_always_run_harness_is_unsure(self):
        outputs, _ = self.plan('echo notchcast-hidden-features-test; : > "$2"\n')
        self.assertEqual(outputs["unsure"], "no harness maps to the diff")

    def misses(self, failed, **env):
        failures = self.root / "failures"
        failures.write_text("".join(f"{name}\n" for name in failed))
        return self.run_script("misses", str(failures), "1", **{"HARNESS_PLANNED": "true", **env})

    def test_a_failure_outside_a_sure_selection_is_a_miss(self):
        stdout = self.misses(["CalcTests", "nc-Example-test"], HARNESS_SELECTED="CalcTests", HARNESS_UNSURE="")
        self.assertIn("::warning title=harness-select::harness-select miss: nc-Example-test failed in shard 1", stdout)
        self.assertIn("failed=CalcTests, nc-Example-test outside=nc-Example-test unsure=no misses=nc-Example-test",
                      stdout)
        self.assertNotIn("miss: CalcTests", stdout)
        self.assertIn("misses=nc-Example-test", self.summary.read_text())

    def test_a_failure_inside_the_selection_is_no_miss(self):
        stdout = self.misses(["CalcTests"], HARNESS_SELECTED="CalcTests", HARNESS_UNSURE="")
        self.assertIn("harness-select shard 1: failed=CalcTests outside=none unsure=no misses=none", stdout)

    def test_an_unsure_selection_has_no_miss(self):
        stdout = self.misses(["nc-Example-test"], HARNESS_SELECTED="CalcTests", HARNESS_UNSURE="runner: project.yml")
        self.assertIn("unsure=runner: project.yml misses=none", stdout)
        self.assertNotIn("harness-select miss:", stdout)

    def test_no_plan_is_not_judged(self):
        stdout = self.misses(["nc-Example-test"], HARNESS_PLANNED="", HARNESS_SELECTED="", HARNESS_UNSURE="")
        self.assertIn("misses=unjudged", stdout)

    def test_a_green_shard_wrote_no_file(self):
        stdout = self.run_script("misses", str(self.root / "absent"), "0", HARNESS_PLANNED="true",
                                 HARNESS_SELECTED="CalcTests", HARNESS_UNSURE="", HARNESS_TESTS="success")
        self.assertIn("harness-select shard 0: failed=none outside=none unsure=no misses=none", stdout)

    def test_a_red_shard_that_named_no_harness_is_not_judged(self):
        for outcome in ("failure", "skipped", ""):
            stdout = self.run_script("misses", str(self.root / "absent"), "0", HARNESS_PLANNED="true",
                                     HARNESS_SELECTED="CalcTests", HARNESS_UNSURE="", HARNESS_TESTS=outcome)
            self.assertIn("unsure=no misses=unjudged", stdout)
        stdout = self.misses([], HARNESS_SELECTED="CalcTests", HARNESS_UNSURE="", HARNESS_TESTS="failure")
        self.assertIn("failed=none outside=none unsure=no misses=unjudged", stdout)


if __name__ == "__main__":
    unittest.main()
