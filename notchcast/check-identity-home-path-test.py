#!/usr/bin/env python3
"""The home-path pattern flags a real user's home and spares shared, placeholder and bundle paths."""
from pathlib import Path
import contextlib
import io
import runpy
import unittest

IDENTITY = runpy.run_path(str(Path(__file__).with_name("check-identity.py")))
# Built at runtime so this file never holds a literal the scanner flags.
USERS = "/" + "Users/"


def flags(text, patterns=IDENTITY["PATTERNS"]):
    with contextlib.redirect_stdout(io.StringIO()) as out:
        failed = IDENTITY["inspect"](text, "probe", patterns)
    return failed, out.getvalue()


class HomePathTest(unittest.TestCase):
    def test_a_home_path_is_flagged_and_redacted(self):
        for text in (USERS + "someone/Code/app", f'let p = "{USERS}a.b-c_9/x"', "file://" + USERS + "x/y"):
            failed, output = flags(text)
            self.assertTrue(failed, text)
            self.assertEqual(output, "check-identity: probe: <home-path>\n")

    def test_shared_placeholders_and_bare_users_pass(self):
        for text in (USERS + "Shared/Notchcast", USERS + "<name>/Library", USERS + "*/Library/Caches",
                     USERS + "someone", "/private" + USERS + "x/y", USERS + "\\(name)/x"):
            self.assertEqual(flags(text), (False, ""), text)

    def test_bundle_scan_ignores_build_paths(self):
        self.assertEqual(flags(USERS + "runner/work/app", IDENTITY["BUNDLE_PATTERNS"]), (False, ""))


if __name__ == "__main__":
    unittest.main()
