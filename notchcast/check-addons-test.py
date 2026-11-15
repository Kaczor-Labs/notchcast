#!/usr/bin/env python3
"""Planted breaches for check-addons.py on a scratch repository: budget, feature paths, registry, reference guard."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
CHECK = Path(__file__).resolve().parent / 'check-addons.py'
NC = 'Tinycast/Features/Notchcast/'
SHOTS = '''struct ShotsAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "shots", title: "", subtitle: "", category: .capture)]
    static let commands = [NotchcastCommand(slug: "shots-area", name: "", symbol: "", switchID: "shots") { _ in }]
}
struct ShotsModule {}
'''


def write(root, path, text):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


class CheckAddonsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        git(self.root, 'init', '-q', '-b', 'main')
        git(self.root, 'config', 'user.email', 'test@example.com')
        git(self.root, 'config', 'user.name', 'Test')
        write(self.root, 'Tinycast/App/AppCore.swift', 'start()\n')
        write(self.root, 'Tinycast/Features/Settings/Catalog.swift', 'keywords: ["shots"]\n')
        self.upstream = self.commit('upstream')
        write(self.root, NC + 'NotchcastRegistry.swift', 'static let addons = [\n]\n')
        write(self.root, NC + 'Core/Service/Core.swift', 'core\n')
        write(self.root, 'notchcast/addons-budget.env', '# budget\nFILES=1\nPLUS=2\nMINUS=0\n')
        self.base = self.commit('base')

    def tearDown(self):
        self.tmp.cleanup()

    def commit(self, message):
        git(self.root, 'add', '-A')
        git(self.root, 'commit', '-q', '-m', message)
        return git(self.root, 'rev-parse', 'HEAD')

    def check(self):
        result = subprocess.run([sys.executable, str(CHECK), '--base', self.base, '--upstream', self.upstream,
                                 '--root', str(self.root)], capture_output=True, text=True)
        return result.returncode, result.stdout + result.stderr

    def add_shots(self):
        write(self.root, NC + 'Shots/ShotsAddon.swift', SHOTS)
        write(self.root, NC + 'NotchcastRegistry.swift', 'static let addons = [\n    ShotsAddon.self,\n]\n')
        write(self.root, 'Tests/nc-Shots-test.swift', 'let id = "shots"\n')

    def test_core_within_budget_passes_and_over_budget_fails(self):
        write(self.root, NC + 'Core/Service/Core.swift', 'core 2\n')
        write(self.root, 'Tinycast/App/AppCore.swift', 'start()\nNotchcastCore.start()\n')
        self.commit('core')
        code, out = self.check()
        self.assertEqual(code, 0, out)
        self.assertIn('upstream touch: 1 files, +1 -0 (budget 1 files, +2 -0)', out)
        write(self.root, 'Tinycast/Features/Settings/Catalog.swift', 'keywords: ["shots", "x"]\n')
        self.commit('core over')
        code, out = self.check()
        self.assertEqual(code, 1, out)
        self.assertIn('over budget', out)

    def test_feature_in_its_folder_passes(self):
        self.add_shots()
        self.commit('feature')
        code, out = self.check()
        self.assertEqual(code, 0, out)
        self.assertIn('add-on gate (feature): feature folders: Shots', out)

    def test_feature_touching_upstream_fails(self):
        self.add_shots()
        write(self.root, 'Tinycast/App/AppCore.swift', 'start()\nshots()\n')
        self.commit('feature')
        code, out = self.check()
        self.assertEqual(code, 1, out)
        self.assertIn('Tinycast/App/AppCore.swift: outside the add-on folders', out)

    def test_registry_line_must_name_an_addon_of_the_branch(self):
        self.add_shots()
        write(self.root, NC + 'NotchcastRegistry.swift', 'static let addons = [\n    ShotsAddon.self,\n    Other.self,\n]\n')
        self.commit('feature')
        code, out = self.check()
        self.assertEqual(code, 1, out)
        self.assertIn('Other is not declared `: NotchcastAddon`', out)
        write(self.root, NC + 'NotchcastRegistry.swift', 'static let addons = [\n    ShotsAddon.self, extra()\n]\n')
        self.commit('feature 2')
        self.assertIn('is not a `<Type>.self,` registry line', self.check()[1])

    def test_guard_catches_ids_slugs_and_types_outside_the_folder(self):
        self.add_shots()
        self.commit('feature')
        self.base = git(self.root, 'rev-parse', 'HEAD')
        for line, token in (('let on = isEnabled("shots")', '"shots"'),
                            ('open("tinycast://command/nc-shots-area")', 'nc-shots-area'),
                            ('let module: ShotsModule? = nil', 'ShotsModule')):
            write(self.root, 'Tinycast/Features/Island/Probe.swift', line + '\n')
            self.commit('island')
            code, out = self.check()
            self.assertEqual(code, 1, out)
            self.assertIn(f"Tinycast/Features/Island/Probe.swift:1: names Shots's", out)
            self.assertIn(token, out)

    def test_guard_allows_dependencies_core_harnesses_and_upstream_lines(self):
        self.add_shots()
        write(self.root, NC + 'Keep/KeepAddon.swift', 'struct KeepAddon: NotchcastAddon {\n'
              '    static let switches = [NotchcastSwitch(id: "keep", title: "", subtitle: "", category: .power, '
              'dependencies: ["shots"])]\n}\n')
        write(self.root, NC + 'NotchcastRegistry.swift',
              'static let addons = [\n    ShotsAddon.self,\n    KeepAddon.self,\n]\n')
        write(self.root, 'Tests/nc-Notchcast-registry-test.swift', 'let frozen = ["shots", "keep"]\n')
        self.commit('two features')
        self.base = git(self.root, 'rev-parse', 'HEAD~1')
        code, out = self.check()
        self.assertNotIn('names', out)
        self.assertIn('Tests/nc-Notchcast-registry-test.swift: outside the add-on folders', out)
        self.assertEqual(code, 1, out)

    def test_a_bad_ref_is_a_tooling_failure(self):
        self.base = 'no-such-ref'
        code, out = self.check()
        self.assertEqual(code, 2, out)
        self.assertIn('tooling failure, not a contract breach', out)


if __name__ == '__main__':
    unittest.main()
