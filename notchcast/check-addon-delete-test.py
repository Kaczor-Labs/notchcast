#!/usr/bin/env python3
"""check-addon-delete.py without a build: rotation, the deletion itself, and breach versus tooling."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location('delete', Path(__file__).resolve().parent / 'check-addon-delete.py')
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


if __name__ == '__main__':
    unittest.main()
