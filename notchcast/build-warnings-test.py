#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECK = Path(__file__).with_name("build-warnings.py")


class BuildWarningsTest(unittest.TestCase):
    def compare(self, base, head):
        with tempfile.TemporaryDirectory() as scratch:
            base_log, head_log = Path(scratch) / "base.log", Path(scratch) / "head.log"
            base_log.write_text(base)
            head_log.write_text(head)
            return subprocess.run(
                [sys.executable, str(CHECK), str(base_log), str(head_log), "/base", "/head"],
                capture_output=True, text=True, timeout=5,
            )

    def test_line_and_checkout_changes_keep_existing_warnings(self):
        result = self.compare(
            "/base/UI.swift:10:2: warning: existing warning\nld: warning: existing link warning\n",
            "/head/UI.swift:20:3: warning: existing warning\nld: warning: existing link warning\n",
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("0 new Debug build warnings vs base", result.stdout)

    def test_new_warnings_include_another_occurrence_of_the_same_warning(self):
        result = self.compare(
            "/base/UI.swift:10:2: warning: existing warning\n",
            "/head/UI.swift:20:3: warning: existing warning\n"
            "/head/UI.swift:21:3: warning: existing warning\n"
            "ld: warning: new link warning\n",
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("::error::2 new Debug build warnings vs base", result.stdout)
        self.assertIn("UI.swift: warning: existing warning", result.stdout)
        self.assertIn("ld: warning: new link warning", result.stdout)

    def test_failed_baseline_build_counts_all_head_warnings(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            head = root / "head"
            tools = root / "notchcast"
            bin_dir = root / "bin"
            runner = root / "runner"
            for directory in (head, tools, bin_dir, runner):
                directory.mkdir()
            shutil.copy(CHECK, tools)
            shutil.copy(CHECK.with_name("ci-build.sh"), tools)
            (tools / "config.env").touch()
            (tools / "ci-xcode.sh").touch()
            (tools / "ci-xcodegen.sh").write_text("XCODEGEN=true\n")
            build = bin_dir / "xcodebuild"
            build.write_text(
                '#!/bin/bash\n'
                'echo "$PWD/UI.swift:10:2: warning: shared warning"\n'
                '[ "${PWD##*/}" = head ]\n'
            )
            build.chmod(0o755)
            env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
            subprocess.run(["git", "init", "-q"], cwd=head, env=env, check=True, timeout=5)
            base = subprocess.check_output(["git", "write-tree"], cwd=head, env=env, text=True, timeout=5).strip()
            result = subprocess.run(
                ["bash", str(tools / "ci-build.sh")], cwd=head, capture_output=True, text=True, timeout=5,
                env={**env, "RUNNER_TEMP": str(runner), "BASE_SHA": base, "NOTCHCAST_HARNESSES_SHARDED": "1",
                     "PATH": f"{bin_dir}{os.pathsep}{env['PATH']}"},
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("::warning::baseline build failed", result.stdout)
        self.assertIn("::error::1 new Debug build warnings vs base", result.stdout)
        self.assertIn("UI.swift: warning: shared warning", result.stdout)


if __name__ == "__main__":
    unittest.main()
