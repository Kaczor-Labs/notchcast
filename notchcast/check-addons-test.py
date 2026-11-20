#!/usr/bin/env python3
"""Planted breaches for check-addons.py on a scratch repository: budget, feature paths, shared lists, reference guard."""
from pathlib import Path
import importlib.util
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
CHECK = Path(__file__).resolve().parent / 'check-addons.py'
NC = 'Tinycast/Features/Notchcast/'
SHOTS = '''// notchcast-addon-order: 30
struct ShotsAddon: NotchcastAddon {
    static let switches = [NotchcastSwitch(id: "shots", title: "", subtitle: "", category: .capture)]
    static let commands = [NotchcastCommand(slug: "shots-area", name: "", symbol: "", switchID: "shots") { _ in }]
}
struct ShotsModule {}
'''


SPEC = importlib.util.spec_from_file_location('check_addons', CHECK)
check_addons = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_addons)


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
        write(self.root, 'notchcast/licenses/borrowed.md', '# Borrowed\n\nLists live in borrowed/.\n')
        write(self.root, 'notchcast/licenses/borrowed/Keep.txt', 'Keep: K.swift ← a/b/K.swift (MIT)\n')
        write(self.root, 'notchcast/config.env', 'CI_SKIP_TESTS="ClipboardTextTests"\nHOSTED_ONLY_TESTS="PasteboardTests"\n')
        write(self.root, 'notchcast/README.public.md', '- **Settings**\n  <!-- addon-tabs:start -->\n'
              '  - **Island**: look.\n  - **Capture**:\n  <!-- addon-tabs:end -->\n')
        self.base = self.commit('base')

    def tearDown(self):
        self.tmp.cleanup()

    def commit(self, message):
        git(self.root, 'add', '-A')
        git(self.root, 'commit', '-q', '-m', message)
        return git(self.root, 'rev-parse', 'HEAD')

    def check(self, mode='feature'):
        result = subprocess.run([sys.executable, str(CHECK), '--mode', mode, '--base', self.base,
                                 '--upstream', self.upstream,
                                 '--root', str(self.root)], capture_output=True, text=True)
        return result.returncode, result.stdout + result.stderr

    def add_shots(self):
        write(self.root, NC + 'Shots/ShotsAddon.swift', SHOTS)
        write(self.root, 'Tests/nc-Shots-test.swift', 'let id = "shots"\n')

    def test_core_within_budget_passes_and_over_budget_fails(self):
        write(self.root, NC + 'Core/Service/Core.swift', 'core 2\n')
        write(self.root, 'Tinycast/App/AppCore.swift', 'start()\nNotchcastCore.start()\n')
        self.commit('core')
        code, out = self.check('core')
        self.assertEqual(code, 0, out)
        self.assertIn('upstream touch: 1 files, +1 -0 (budget 1 files, +2 -0)', out)
        write(self.root, 'Tinycast/Features/Settings/Catalog.swift', 'keywords: ["shots", "x"]\n')
        self.commit('core over')
        code, out = self.check('core')
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

    def test_a_hand_edit_of_a_shared_list_fails_on_every_branch(self):
        readme = (self.root / 'notchcast/README.public.md').read_text()
        cases = (
            (NC + 'NotchcastRegistry.swift', 'static let addons = [\n    ShotsAddon.self,\n]\n',
             f'{NC}NotchcastRegistry.swift: generated from each add-on'),
            ('notchcast/licenses/borrowed.md', '# Borrowed\n\nLists live in borrowed/.\nShots: A.swift ← x/y/A.swift (MIT)\n',
             'belongs in notchcast/licenses/borrowed/Shots.txt'),
            ('notchcast/README.public.md', readme.replace('  - **Capture**:', '  - **Capture**: screenshots'),
             'notchcast/README.public.md:4: a phrase on a tab line'),
            ('notchcast/config.env', 'CI_SKIP_TESTS="ClipboardTextTests"\nHOSTED_ONLY_TESTS="PasteboardTests nc-Shots-test"\n',
             'config.env:2: names the fork harness nc-Shots-test; drop it there and give Tests/nc-Shots-test.swift '
             'a `// notchcast-hosted-only`, `-linux-ok` or `-ci-skip` line'),
        )
        for path, text, needle in cases:
            for mode in ('none', 'feature'):
                git(self.root, 'reset', '-q', '--hard', self.base)
                self.add_shots()
                write(self.root, path, text)
                self.commit('hand edit')
                code, out = self.check(mode)
                self.assertEqual(code, 1, out)
                self.assertIn(needle, out)

    def test_a_fork_harness_name_the_branch_did_not_add_passes(self):
        write(self.root, 'notchcast/config.env', 'CI_SKIP_TESTS=""\nHOSTED_ONLY_TESTS="PasteboardTests nc-Old-test"\n')
        self.base = self.commit('main before the tags')
        self.add_shots()
        write(self.root, 'Tests/nc-Shots-test.swift', '// notchcast-hosted-only\nlet id = "shots"\n')
        self.commit('feature')
        code, out = self.check('none')
        self.assertEqual(code, 0, out)

    def test_its_own_files_carry_an_addon_and_a_new_tab_line_is_core(self):
        self.add_shots()
        write(self.root, 'notchcast/licenses/borrowed/Shots.txt', 'Shots: A.swift ← x/y/A.swift (MIT)\n')
        write(self.root, 'Tests/nc-Shots-test.swift', '// notchcast-hosted-only\nlet id = "shots"\n')
        self.commit('feature')
        code, out = self.check()
        self.assertEqual(code, 0, out)
        readme = (self.root / 'notchcast/README.public.md').read_text()
        write(self.root, 'notchcast/README.public.md', readme.replace('  - **Capture**:', '  - **Capture**:\n  - **Power**:'))
        self.commit('core adds a tab')
        self.assertEqual(self.check('none')[0], 0)

    def test_a_branch_that_changes_the_generator_may_rewrite_what_it_generates(self):
        write(self.root, NC + 'NotchcastRegistry.swift', '// Generated\nstatic let addons = [\n]\n')
        write(self.root, 'notchcast/addons.py', 'print("generator")\n')
        self.commit('generator')
        code, out = self.check('none')
        self.assertEqual(code, 0, out)

    def test_the_generator_exemption_covers_the_registry_alone(self):
        readme = (self.root / 'notchcast/README.public.md').read_text()
        write(self.root, 'notchcast/addons.py', 'print("generator")\n')
        write(self.root, 'notchcast/README.public.md', readme.replace('  - **Capture**:', '  - **Capture**: screenshots'))
        self.commit('generator and a phrase')
        code, out = self.check('none')
        self.assertEqual(code, 1, out)
        self.assertIn('a phrase on a tab line', out)

    def test_core_text_on_a_tab_line_stays_editable(self):
        readme = (self.root / 'notchcast/README.public.md').read_text()
        write(self.root, 'notchcast/README.public.md', readme.replace('**Island**: look.', '**Island**: look, hide.'))
        self.commit('core edits the island line')
        code, out = self.check('none')
        self.assertEqual(code, 0, out)

    def test_prose_in_the_licence_header_stays_editable(self):
        write(self.root, 'notchcast/licenses/borrowed.md', '# Borrowed\n\nLists live in borrowed/, one `<Folder>: <file> ← <repo>/<file> (<licence>)` each.\n')
        self.commit('core rewords the header')
        code, out = self.check('none')
        self.assertEqual(code, 0, out)

    def test_a_second_list_line_or_an_odd_licence_line_still_fails(self):
        cases = (
            ('notchcast/config.env', 'CI_SKIP_TESTS="ClipboardTextTests"\nHOSTED_ONLY_TESTS="PasteboardTests"\n'
             'EXTRA="nc-Shots-test"\nHOSTED_ONLY_TESTS+=" $EXTRA"\n', 'names the fork harness nc-Shots-test'),
            ('notchcast/licenses/borrowed.md', '# Borrowed\n\nLists live in borrowed/.\n`Shots`: `A.swift` ← `x/y/A.swift` (MIT)\n',
             'belongs in notchcast/licenses/borrowed/<Folder>.txt'),
            ('notchcast/README.public.md', '- **Settings**\n  <!-- addon-tabs:start -->\n  - **Island**: look.\n  - **Capture**:\n'
             '  - **Brand New**: shots.\n  <!-- addon-tabs:end -->\n', 'README.public.md:5: a phrase on a tab line'),
            ('notchcast/README.public.md', '- **Settings**\n  <!-- addon-tabs:start -->\n  - **Island**: look.\n  - **Capture**:\n'
             '  * **Capture**: shots.\n  <!-- addon-tabs:end -->\n', 'README.public.md:5: a phrase on a tab line'),
            ('notchcast/config.env', 'CI_SKIP_TESTS="ClipboardTextTests"\nHOSTED_ONLY_TESTS="PasteboardTests"\n'
             'HOSTED_ONLY_TESTS="$HOSTED_ONLY_TESTS nc-Shots-test"\n', 'names the fork harness nc-Shots-test'),
            ('notchcast/licenses/borrowed.md', '# Borrowed\n\nLists live in borrowed/.\nShots: A.swift, B.swift ← x/y (MIT)\n',
             'belongs in notchcast/licenses/borrowed/<Folder>.txt'),
        )
        for path, text, needle in cases:
            git(self.root, 'reset', '-q', '--hard', self.base)
            write(self.root, path, text)
            self.commit('hand edit')
            code, out = self.check('none')
            self.assertEqual(code, 1, out)
            self.assertIn(needle, out)

    def test_guard_catches_ids_slugs_and_types_outside_the_folder(self):
        self.add_shots()
        self.commit('feature')
        self.base = git(self.root, 'rev-parse', 'HEAD')
        for line, token in (('let on = isEnabled("shots")', '"shots"'),
                            ('open("tinycast://command/nc-shots-area")', 'nc-shots-area'),
                            ('let module: ShotsModule? = nil', 'ShotsModule')):
            write(self.root, 'Tinycast/Features/Island/Probe.swift', line + '\n')
            self.commit('island')
            code, out = self.check('none')
            self.assertEqual(code, 1, out)
            self.assertIn(f"Tinycast/Features/Island/Probe.swift:1: names Shots's", out)
            self.assertIn(token, out)

    def test_guard_allows_dependencies_core_harnesses_and_upstream_lines(self):
        self.add_shots()
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 40\nstruct KeepAddon: NotchcastAddon {\n'
              '    static let switches = [NotchcastSwitch(id: "keep", title: "", subtitle: "", category: .power, '
              'dependencies: ["shots"])]\n}\n')
        write(self.root, 'Tests/nc-Notchcast-registry-test.swift', 'let frozen = ["shots", "keep"]\n')
        self.commit('two features')
        self.base = git(self.root, 'rev-parse', 'HEAD~1')
        code, out = self.check()
        self.assertNotIn('names', out)
        self.assertIn('Tests/nc-Notchcast-registry-test.swift: outside the add-on folders', out)
        self.assertEqual(code, 1, out)

    def test_guard_skips_nested_types_strings_and_comments(self):
        self.add_shots()
        write(self.root, NC + 'Shots/ShotsAddon.swift', SHOTS + 'struct ShotsKeys {\n    enum Press { case down }\n}\n'
              'private struct Start {}\nfileprivate final class Pad {}\n@MainActor package enum ShotsLimits {}\n')
        self.commit('feature')
        self.base = git(self.root, 'rev-parse', 'HEAD')
        write(self.root, 'Tinycast/Features/Onboarding/Ready.swift',
              'let text = Text("Press \\(chip(caps)) anytime", tableName: "N") // ShotsModule waits\n'
              '/* ShotsKeys */ let copy = """\n    Press ShotsModule\n    """\nlet own = Keyboard.Press.down\n'
              'let pad = Pad(start: Start.now)\n')
        self.commit('onboarding copy')
        code, out = self.check('none')
        self.assertEqual(code, 0, out)
        write(self.root, 'Tinycast/Features/Onboarding/Ready.swift', 'let text = Text("Press \\(ShotsKeys.self)")\n')
        self.commit('real reference')
        code, out = self.check('none')
        self.assertEqual(code, 1, out)
        self.assertIn("Tinycast/Features/Onboarding/Ready.swift:1: names Shots's ShotsKeys", out)
        write(self.root, 'Tinycast/Features/Onboarding/Ready.swift', 'let cap = ShotsLimits.self\n')
        self.commit('package reference')
        code, out = self.check('none')
        self.assertIn("Tinycast/Features/Onboarding/Ready.swift:1: names Shots's ShotsLimits", out)

    def add_keep(self):
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 10\nstruct KeepAddon: NotchcastAddon {\n}\n')
        self.commit('keep')
        self.base = git(self.root, 'rev-parse', 'HEAD')

    def test_a_feature_owns_only_the_folder_its_order_line_names(self):
        self.add_keep()
        self.add_shots()
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 10\nstruct KeepAddon: NotchcastAddon {\n    let x = 1\n}\n')
        self.commit('shots edits keep')
        code, out = self.check()
        self.assertEqual(code, 1, out)
        self.assertIn(f"{NC}Keep/KeepAddon.swift: outside the add-on folders ['Shots']", out)

    def test_renumbering_another_addon_claims_no_folder(self):
        self.add_keep()
        self.add_shots()
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 40\nstruct KeepAddon: NotchcastAddon {\n}\n')
        self.commit('shots renumbers keep')
        code, out = self.check()
        self.assertEqual(code, 1, out)
        self.assertIn(f"{NC}Keep/KeepAddon.swift: outside the add-on folders ['Shots']", out)

    def test_an_edit_without_an_order_line_owns_one_folder(self):
        self.add_keep()
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 10\nstruct KeepAddon: NotchcastAddon {\n    let x = 1\n}\n')
        self.commit('keep fix')
        code, out = self.check()
        self.assertEqual(code, 0, out)
        self.assertIn('add-on gate (feature): feature folders: Keep', out)
        write(self.root, NC + 'Other/Other.swift', 'struct Other {}\n')
        self.commit('two folders')
        code, out = self.check()
        self.assertEqual(code, 1, out)
        self.assertIn('outside the add-on folders (none)', out)

    def test_a_core_edit_does_not_turn_a_feature_into_budget_mode(self):
        self.add_shots()
        write(self.root, NC + 'Core/Service/Core.swift', 'core 2\n')
        self.commit('feature edits core')
        code, out = self.check()
        self.assertEqual(code, 1, out)
        self.assertNotIn('upstream touch', out)
        self.assertIn(f'{NC}Core/Service/Core.swift: outside the add-on folders', out)

    def test_a_feature_writes_only_its_own_licence_list(self):
        self.add_shots()
        write(self.root, 'notchcast/licenses/borrowed/Shots.txt',
              'Shots: Shots/Grab.swift ← someone/shots/Sources/Grab.swift (GPL-3.0-or-later)\n')
        self.commit('feature with licence')
        code, out = self.check()
        self.assertEqual(code, 0, out)
        for path, text, needle in (
                ('notchcast/licenses/borrowed/Keep.txt', 'Keep: X.swift ← a/b/X.swift (MIT)\n', 'the licence list of Keep'),
                ('notchcast/licenses/borrowed/Shots.txt', 'Shots: free text\n', 'is not a `Shots: <our file>'),
                ('notchcast/licenses/borrowed/Shots.txt', 'Keep: X.swift ← a/b/X.swift (MIT)\n', 'is not a `Shots: <our file>')):
            git(self.root, 'reset', '-q', '--hard', self.base)
            self.add_shots()
            write(self.root, path, text)
            self.commit('bad licence line')
            code, out = self.check()
            self.assertEqual(code, 1, out)
            self.assertIn(needle, out)

    def test_the_mode_is_required(self):
        result = subprocess.run([sys.executable, str(CHECK), '--base', self.base, '--root', str(self.root)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('--mode', result.stderr)

    def test_the_branch_name_picks_the_mode(self):
        # A rebased core is pushed under a new number, since force-pushing is never allowed.
        for branch, mode in (('v2/addons-core', 'core'), ('v2/addons-core-3', 'core'), ('v2/addons-core-12', 'core'),
                             ('v2/addons-core-3-fix', 'feature'), ('v2/addons-core-3foo', 'feature'),
                             ('v2/addons-core-x', 'feature'), ('v2/addons-core-', 'feature'),
                             ('v2/addons-shots', 'feature'), ('v2/stack', 'none'), ('', 'none')):
            self.assertEqual(check_addons.mode_for_branch(branch, self.root, self.base, 'HEAD', []), mode, branch)

    def by_branch(self, branch):
        result = subprocess.run([sys.executable, str(CHECK), '--branch', branch, '--base', self.base,
                                 '--upstream', self.upstream, '--root', str(self.root)], capture_output=True, text=True)
        return result.returncode, result.stdout + result.stderr

    def test_any_branch_that_adds_an_addon_is_a_feature(self):
        self.add_shots()
        write(self.root, 'Tinycast/App/AppCore.swift', 'start()\nshots()\n')
        self.commit('feature on a gate branch')
        code, out = self.by_branch('g-123abc')
        self.assertEqual(code, 1, out)
        self.assertIn('add-on gate (feature): feature folders: Shots', out)
        self.assertIn('Tinycast/App/AppCore.swift: outside the add-on folders', out)

    def test_a_sweep_across_addons_runs_no_feature_gate(self):
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 10\nstruct KeepAddon: NotchcastAddon {}\n')
        self.add_shots()
        self.base = self.commit('main with two add-ons')
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 10\n// notchcast-readme: Capture: k\n'
              'struct KeepAddon: NotchcastAddon {}\n')
        write(self.root, NC + 'Shots/ShotsAddon.swift', SHOTS.replace('30\n', '30\n// notchcast-readme: Capture: s\n', 1))
        write(self.root, 'notchcast/tool.py', 'pass\n')
        self.commit('sweep')
        code, out = self.by_branch('g-123abc')
        self.assertEqual(code, 0, out)
        self.assertIn('add-on gate (none):', out)
        write(self.root, NC + 'Keep/KeepAddon.swift', '// notchcast-addon-order: 10\nstruct KeepAddon: NotchcastAddon {}\n')
        self.commit('one add-on and a tool')
        code, out = self.by_branch('g-123abc')
        self.assertEqual(code, 1, out)
        self.assertIn('notchcast/tool.py: outside the add-on folders', out)

    def test_branch_runs_the_derived_mode(self):
        result = subprocess.run([sys.executable, str(CHECK), '--branch', 'v2/addons-core-4', '--base', self.base,
                                 '--upstream', self.upstream, '--root', str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('add-on gate (core):', result.stdout)

    def test_a_bad_ref_is_a_tooling_failure(self):
        self.base = 'no-such-ref'
        code, out = self.check()
        self.assertEqual(code, 2, out)
        self.assertIn('tooling failure, not a contract breach', out)


if __name__ == '__main__':
    unittest.main()
