#!/usr/bin/env python3
"""check-addon-delete.py without a build: rotation, the deletion itself, and breach versus tooling."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parent / 'check-addon-delete.py'
SPEC = importlib.util.spec_from_file_location('delete', SCRIPT)
delete = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(delete)
NC = 'Tinycast/Features/Notchcast/'


def write(root, path, text):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)


class DeleteTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tree = Path(self.tmp.name)
        write(self.tree, NC + 'NotchcastRegistry.swift', 'static let addons = [\n    ShotsAddon.self,\n    KeepAddon.self,\n]\n')
        write(self.tree, NC + 'Shots/ShotsAddon.swift', 'struct ShotsAddon: NotchcastAddon {}\n')
        write(self.tree, NC + 'Keep/KeepAddon.swift', '@MainActor enum KeepAddon: NotchcastAddon {}\n')
        write(self.tree, 'Tests/nc-Shots-test.swift', '')
        write(self.tree, 'Tests/nc-Shotsy-test.swift', '')
        write(self.tree, 'notchcast/licenses/borrowed.md', '# Borrowed\n\nShots: A.swift ← x/a.swift (MIT)\n'
              'Shotsy: B.swift ← x/b.swift (MIT)\nKeep: C.swift ← x/c.swift (MIT)\nShots: D.swift ← x/d.swift (MIT)\n')

    def tearDown(self):
        self.tmp.cleanup()

    def test_rotation_is_stable_per_sha(self):
        self.assertEqual(delete.rotate_pick(['A', 'B', 'C'], 'f' * 40), delete.rotate_pick(['A', 'B', 'C'], 'f' * 40))
        self.assertEqual({delete.rotate_pick(['A', 'B'], sha) for sha in ('0' * 40, '1' * 40)}, {'A', 'B'})

    def test_deleting_removes_folder_line_and_its_tests_only(self):
        delete.delete_folder(self.tree, 'Shots')
        self.assertFalse((self.tree / NC / 'Shots').exists())
        self.assertEqual((self.tree / NC / 'NotchcastRegistry.swift').read_text(),
                         'static let addons = [\n    KeepAddon.self,\n]\n')
        self.assertFalse((self.tree / 'Tests/nc-Shots-test.swift').exists())
        self.assertTrue((self.tree / 'Tests/nc-Shotsy-test.swift').exists())
        self.assertEqual((self.tree / 'notchcast/licenses/borrowed.md').read_text(),
                         '# Borrowed\n\nShotsy: B.swift ← x/b.swift (MIT)\nKeep: C.swift ← x/c.swift (MIT)\n')

    def test_a_missing_registry_line_is_a_breach(self):
        write(self.tree, NC + 'NotchcastRegistry.swift', 'static let addons = [\n]\n')
        with self.assertRaisesRegex(delete.Breach, 'no line for ShotsAddon'):
            delete.delete_folder(self.tree, 'Shots')

    def test_an_orphan_string_is_a_breach(self):
        write(self.tree, 'Tinycast/Features/Island/X.swift', 'String(localized: "Hi", table: "NotchcastShots")\n')
        with self.assertRaisesRegex(delete.Breach, 'table NotchcastShots remain'):
            delete.delete_folder(self.tree, 'Shots')

    def test_a_folder_without_an_addon_is_tooling(self):
        write(self.tree, NC + 'Empty/Notes.swift', 'struct Notes {}\n')
        with self.assertRaises(delete.Tooling):
            delete.delete_folder(self.tree, 'Empty')

    def test_step_classifies_failures(self):
        log = self.tree / 'step.log'
        delete.step('build', ['true'], self.tree, log, None)
        with self.assertRaisesRegex(delete.Breach, 'build failed; log: '):
            delete.step('build', ['sh', '-c', 'echo "A.swift:3:9: error: cannot find X"; exit 65'], self.tree, log, None)
        with self.assertRaisesRegex(delete.Tooling, 'without a Swift error'):
            delete.step('build', ['sh', '-c', 'echo "database is locked"; exit 65'], self.tree, log, None)
        with self.assertRaisesRegex(delete.Breach, 'run-tests failed'):
            delete.step('run-tests', ['sh', '-c', 'echo "FAIL  nc-Keep-test  did not compile"; exit 1'], self.tree, log, None)
        with self.assertRaisesRegex(delete.Tooling, 'xcodegen failed'):
            delete.step('xcodegen', ['false'], self.tree, log, None)
        with self.assertRaisesRegex(delete.Tooling, 'could not start'):
            delete.step('xcodegen', ['/no/such/xcodegen'], self.tree, log, None)

    def test_a_fork_harness_the_runner_skipped_is_reported(self):
        log = ('[1/3] \x1b[32mok\x1b[0m    nc-Keep-test       0.0s\n'
               '[2/3] \x1b[31mFAIL\x1b[0m  notchcast-hidden-features-test\n')
        names = ['nc-Keep-test', 'nc-Other-test', 'notchcast-hidden-features-test']
        self.assertEqual(delete.unreported(log, names), ['nc-Other-test'])

    def test_fork_harnesses_come_from_harness_inputs(self):
        write(self.tree, 'notchcast/harness_inputs.py',
              'print("Tests/nc-Keep-test.swift\\t1\\tA.swift")\nprint("Tests/BarTests.swift\\t0\\t")\n')
        self.assertEqual(delete.fork_harnesses(self.tree, None), ['nc-Keep-test'])
        write(self.tree, 'notchcast/harness_inputs.py', 'import sys\nsys.exit("bad kit")\n')
        with self.assertRaisesRegex(delete.Tooling, 'harness_inputs.py failed: bad kit'):
            delete.fork_harnesses(self.tree, None)


FAKE_QUEUE = '''import os, subprocess, sys
with open(os.environ["QUEUE_CALLS"], "a") as calls:
    calls.write(" ".join(sys.argv[1:]) + "\\n")
if os.environ.get("CHAD_BUILD_QUEUE_SLOT") or os.environ.get("FAKE_QUEUE_EXIT"):
    sys.exit(int(os.environ.get("FAKE_QUEUE_EXIT", 99)))
sys.exit(subprocess.run(sys.argv[3:], env=dict(os.environ, CHAD_BUILD_QUEUE_SLOT="1")).returncode)
'''


class QueueTest(unittest.TestCase):
    """A real run that fails right after the clone: Shots is a breach (no registry line), Empty is tooling."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.repo = root / 'repo'
        write(self.repo, NC + 'NotchcastRegistry.swift', 'static let addons = [\n]\n')
        write(self.repo, NC + 'Shots/ShotsAddon.swift', 'struct ShotsAddon: NotchcastAddon {}\n')
        write(self.repo, NC + 'Empty/Notes.swift', 'struct Notes {}\n')
        git_env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t',
                       GIT_COMMITTER_EMAIL='t@t')
        for command in (['init', '-q'], ['add', '.'], ['commit', '-qm', 'fixture']):
            subprocess.run(['git', *command], cwd=self.repo, env=git_env, check=True)
        self.sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.repo, text=True).strip()
        write(root, 'queue.py', FAKE_QUEUE)
        (root / 'home').mkdir()
        self.calls = root / 'calls'
        self.calls.touch()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('NOTCHCAST_', 'CHAD_BUILD_QUEUE'))}
        self.env.update(HOME=str(root / 'home'), QUEUE_CALLS=str(self.calls), NOTCHCAST_DELETE_SCRATCH=str(root),
                        NOTCHCAST_BUILD_QUEUE=f'{sys.executable} {root / "queue.py"}')

    def tearDown(self):
        self.tmp.cleanup()

    def run_delete(self, folder, **env):
        return subprocess.run([sys.executable, str(SCRIPT), folder], cwd=self.repo, env={**self.env, **env},
                              capture_output=True, text=True)

    def calls_made(self):
        return self.calls.read_text().splitlines()

    def test_one_hold_wraps_the_whole_run_and_passes_its_exit_through(self):
        for folder, code in (('Shots', 1), ('Empty', 2)):
            self.calls.write_text('')
            result = self.run_delete(folder)
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
            self.assertEqual(self.calls_made(), [f'hold -- {sys.executable} {SCRIPT} {folder} --ref {self.sha}'])

    def test_inside_a_slot_or_without_the_hook_it_runs_directly(self):
        self.assertEqual(self.run_delete('Shots', CHAD_BUILD_QUEUE_SLOT='2').returncode, 1)
        self.assertEqual(self.run_delete('Shots', NOTCHCAST_BUILD_QUEUE='').returncode, 1)
        self.assertEqual(self.calls_made(), [])

    def test_a_queue_refusal_is_tooling_not_a_breach(self):
        result = self.run_delete('Shots', FAKE_QUEUE_EXIT='3')
        self.assertEqual(result.returncode, 2)
        self.assertIn('tooling failure, not a contract breach: build queue exited 3', result.stdout)


if __name__ == '__main__':
    unittest.main()
