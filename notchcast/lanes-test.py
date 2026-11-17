#!/usr/bin/env python3
"""Prove lanes.py skips a lane only for docs or build-free notchcast/ files, and runs everything otherwise."""
from pathlib import Path
import subprocess
import tempfile
import unittest

LANES = Path(__file__).resolve().with_name("lanes.py")
TREE = {
    "README.md": "readme\n", "docs/ui.md": "ui\n", "notchcast/docs/x.md": "doc\n",
    "notchcast/ci-build.sh": "bash notchcast/ci-xcode.sh\npython3 notchcast/check-config.py\n",
    "notchcast/ci-xcode.sh": "source \"$(dirname \"$0\")/config.env\"\n", "notchcast/config.env": "A=1\n",
    "notchcast/check-config.py": "from harness_inputs import harnesses\n", "notchcast/harness_inputs.py": "x = 1\n",
    "notchcast/licenses/borrowed.md": "list\n", "notchcast/vendor/Engine/Thing.swift": "struct Thing {}\n",
    "notchcast/actions/tests/action.yml": "run: bash ../../ci-tests.sh\n", "notchcast/ci-tests.sh": "true\n",
    "notchcast/tool.sh": "echo tool\n", "notchcast/tool-test.sh": "bash notchcast/tool.sh\n",
    "notchcast/actions/route/action.yml": "run: python3 \"$GITHUB_ACTION_PATH/../../runner/route.py\"\n",
    "notchcast/runner/route.py": "print()\n", "notchcast/lanes.py": "print()\n", "NOTICE.md": "notice\n",
    "notchcast/vendor/Engine/README.md": "engine\n",
    "notchcast/xins.py": "print()\n", "project.yml": "path: notchcast/vendor/Engine\n",
    "Tinycast/App.swift": "@main struct App {}\n", "Tinycast/README.md": "bundled\n", ".github/CONTRIBUTING.md": "c\n",
    "LICENSE": "mit\n",
}


class LanesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.git("init", "-q")
        self.commit(TREE)
        self.base = self.git("rev-parse", "HEAD")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                                       cwd=self.root, text=True).strip()

    def commit(self, files, removed=()):
        for path, text in files.items():
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_text(text)
        for path in removed:
            (self.root / path).unlink()
        self.git("add", "-A")
        self.git("commit", "-qm", "change", "--allow-empty")

    def lanes(self, *args):
        return subprocess.check_output(["python3", str(LANES), *args], cwd=self.root, text=True,
                                       stderr=subprocess.DEVNULL).split()

    def change(self, path, removed=False):
        self.git("reset", "-q", "--hard", self.base)
        self.commit({} if removed else {path: "changed\n"}, [path] if removed else [])
        return self.lanes(self.base, "HEAD")

    def test_lanes(self):
        none, scripts, every = ["build=false", "scripts=false"], ["build=false", "scripts=true"], ["build=true", "scripts=true"]
        cases = {"README.md": none, "docs/ui.md": none, "notchcast/docs/x.md": none, "docs/shot.png": none,
                 "notchcast/xins.py": scripts, "notchcast/tool.sh": scripts, "notchcast/new-tool.py": scripts,
                 "notchcast/ci-build.sh": every, "notchcast/ci-xcode.sh": every, "notchcast/config.env": every,
                 "notchcast/harness_inputs.py": every, "notchcast/ci-tests.sh": every,
                 "notchcast/vendor/Engine/Thing.swift": every, "notchcast/licenses/borrowed.md": scripts,
                 "notchcast/actions/route/action.yml": every, "notchcast/runner/route.py": every,
                 "notchcast/lanes.py": every, "notchcast/actions/new/action.yml": every, "NOTICE.md": every,
                 "notchcast/vendor/Engine/README.md": every,
                 "Tinycast/App.swift": every, "Tinycast/README.md": every, ".github/CONTRIBUTING.md": every,
                 "project.yml": every, "LICENSE": every, "Unknown/thing.txt": every}
        for path, expected in cases.items():
            self.assertEqual(self.change(path), expected, path)
        self.assertEqual(self.change("notchcast/config.env", removed=True), every)
        self.assertEqual(self.change("notchcast/xins.py", removed=True), scripts)
        print("PASS docs skip both lanes, build-free scripts skip the build, everything else runs both")

    def test_any_doubt_runs_everything(self):
        every = ["build=true", "scripts=true"]
        self.assertEqual(self.lanes("", "HEAD"), every)
        self.assertEqual(self.lanes("no-such-commit", "HEAD"), every)
        self.assertEqual(self.lanes(), every)
        print("PASS a missing or unreadable base runs every lane")


if __name__ == "__main__":
    unittest.main()
