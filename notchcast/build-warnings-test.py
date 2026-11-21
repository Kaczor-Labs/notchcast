#!/usr/bin/env python3
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


if __name__ == "__main__":
    unittest.main()
