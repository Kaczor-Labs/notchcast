#!/usr/bin/env python3
"""check-addon-delete.py without a build: rotation, the deletion itself, and breach versus tooling."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

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


FAKE_QUEUE = """import os, subprocess, sys, time
with open(os.environ["QUEUE_CALLS"], "a") as calls:
    calls.write(" ".join(sys.argv[1:]) + "\\n")
if os.environ.get("FAKE_QUEUE_SLEEP"):
    time.sleep(30)
if "FAKE_QUEUE_STATUS" in os.environ:
    open(os.environ["NOTCHCAST_DELETE_STATUS"], "w").write(os.environ["FAKE_QUEUE_STATUS"])
    sys.exit(0)
if os.environ.get("CHAD_BUILD_QUEUE_SLOT") or os.environ.get("FAKE_QUEUE_EXIT"):
    sys.exit(int(os.environ.get("FAKE_QUEUE_EXIT", 99)))
sys.exit(subprocess.run(sys.argv[3:], env=dict(os.environ, CHAD_BUILD_QUEUE_SLOT="1")).returncode)
"""
BREACH = 'contract breach: Shots: registry has no line for ShotsAddon'
TOOLING = 'tooling failure, not a contract breach: '


class QueueTest(unittest.TestCase):
    """A real run with stub build tools: Keep passes, Shots is a breach (no registry line), Empty is tooling."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.repo = root / 'repo'
        write(self.repo, NC + 'NotchcastRegistry.swift', 'static let addons = [\n    KeepAddon.self,\n]\n')
        write(self.repo, NC + 'Keep/KeepAddon.swift', 'struct KeepAddon: NotchcastAddon {}\n')
        write(self.repo, NC + 'Shots/ShotsAddon.swift', 'struct ShotsAddon: NotchcastAddon {}\n')
        write(self.repo, NC + 'Empty/Notes.swift', 'struct Notes {}\n')
        write(self.repo, 'notchcast/harness_inputs.py', '')
        write(self.repo, 'Scripts/run-tests.sh', '#!/bin/sh\n')
        (self.repo / 'Scripts/run-tests.sh').chmod(0o755)
        git_env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t',
                       GIT_COMMITTER_EMAIL='t@t')
        for command in (['init', '-q'], ['add', '.'], ['commit', '-qm', 'fixture']):
            subprocess.run(['git', *command], cwd=self.repo, env=git_env, check=True)
        self.sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.repo, text=True).strip()
        for tool in ('xcodegen', 'xcodebuild'):
            write(root, f'bin/{tool}', '#!/bin/sh\n')
            (root / 'bin' / tool).chmod(0o755)
        write(root, 'queue.py', FAKE_QUEUE)
        (root / 'home').mkdir()
        self.calls = root / 'calls'
        self.calls.touch()
        self.hook = f'{sys.executable} {root / "queue.py"}'
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(('NOTCHCAST_', 'CHAD_BUILD_QUEUE', 'XCODEGEN'))}
        self.env.update(HOME=str(root / 'home'), QUEUE_CALLS=str(self.calls), NOTCHCAST_DELETE_SCRATCH=str(root),
                        NOTCHCAST_BUILD_QUEUE=self.hook, PATH=f'{root / "bin"}:{os.environ["PATH"]}')

    def tearDown(self):
        self.tmp.cleanup()

    def run_delete(self, *args, **env):
        result = subprocess.run([sys.executable, str(SCRIPT), *args], cwd=self.repo, env={**self.env, **env},
                                capture_output=True, text=True)
        self.assertNotIn('Traceback', result.stdout + result.stderr)
        return result

    def assert_verdict(self, result, code, text):
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertIn(text, result.stdout)

    def hold(self, *target):
        return f"hold -- {sys.executable} {SCRIPT} --ref {self.sha} {' '.join(target)}"

    def calls_made(self):
        return self.calls.read_text().splitlines()

    def private_env(self, text):
        write(Path(self.env['HOME']), '.config/notchcast/private.env', text)

    def test_one_hold_wraps_the_whole_run_and_returns_the_inner_verdict(self):
        cases = (('Keep', 0, f'PASS delete Keep at {self.sha[:12]}'), ('Shots', 1, BREACH),
                 ('Empty', 2, TOOLING + 'Empty: no type'))
        for folder, code, text in cases:
            self.calls.write_text('')
            self.assert_verdict(self.run_delete(folder), code, text)
            self.assertEqual(self.calls_made(), [self.hold('--', folder)])

    def test_options_after_a_separator_still_get_one_pinned_ref(self):
        self.assert_verdict(self.run_delete('--ref', 'HEAD', '--', 'Shots'), 1, BREACH)
        self.assertEqual(self.calls_made(), [self.hold('--', 'Shots')])
        self.calls.write_text('')
        self.assert_verdict(self.run_delete('--all'), 1, BREACH)
        self.assertEqual(self.calls_made(), [self.hold('--all')])

    def test_inside_a_slot_or_without_the_hook_it_runs_directly(self):
        self.assert_verdict(self.run_delete('Shots', CHAD_BUILD_QUEUE_SLOT='2'), 1, BREACH)
        self.assert_verdict(self.run_delete('Shots', NOTCHCAST_BUILD_QUEUE=''), 1, BREACH)
        self.assertEqual(self.calls_made(), [])

    def test_a_queue_that_fails_or_cannot_start_is_tooling_not_a_breach(self):
        for code in ('1', '3'):
            self.assert_verdict(self.run_delete('Shots', FAKE_QUEUE_EXIT=code), 2,
                                TOOLING + f'build queue exited {code} without a valid verdict')
        self.assert_verdict(self.run_delete('Shots', NOTCHCAST_BUILD_QUEUE='/no/such/queue'), 2,
                            TOOLING + 'build queue could not start')

    def test_a_signal_is_forwarded_to_the_queue_and_is_tooling(self):
        for signum in (signal.SIGTERM, signal.SIGHUP):
            self.calls.write_text('')
            run = subprocess.Popen([sys.executable, str(SCRIPT), 'Shots'], cwd=self.repo, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env={**self.env, 'FAKE_QUEUE_SLEEP': '1'})
            for _ in range(100):
                if self.calls_made():
                    break
                time.sleep(0.05)
            run.send_signal(signum)
            stdout, stderr = run.communicate(timeout=10)
            self.assertEqual(run.returncode, 2, stdout + stderr)
            self.assertIn(TOOLING + f'stopped by signal {signum.value}', stdout)
            self.assertNotIn('Traceback', stdout + stderr)

    def test_an_empty_or_unknown_status_is_tooling_not_a_crash(self):
        for status in ('', '7', 'full disk'):
            self.assert_verdict(self.run_delete('Shots', FAKE_QUEUE_STATUS=status), 2,
                                TOOLING + 'build queue exited 0 without a valid verdict')

    def queued_with_a_signal_during(self, patched):
        """Calls queued() in this process, raising SIGTERM inside `patched` before the queue is launched."""
        real = getattr(getattr(delete, patched[0]), patched[1])

        def signalling(*args, **kwargs):
            os.kill(os.getpid(), signal.SIGTERM)
            return real(*args, **kwargs)

        saved = {signum: signal.getsignal(signum) for signum in (signal.SIGINT, signal.SIGTERM)}
        out = io.StringIO()
        try:
            with mock.patch.object(getattr(delete, patched[0]), patched[1], signalling), \
                    mock.patch.dict(os.environ, QUEUE_CALLS=str(self.calls), FAKE_QUEUE_SLEEP='1'), \
                    contextlib.redirect_stdout(out):
                started = time.monotonic()
                code = delete.queued(self.hook.split(), self.sha, ['--', 'Shots'])
        finally:
            for signum, handler in saved.items():
                signal.signal(signum, handler)
        self.assertEqual(code, 2, out.getvalue())
        self.assertIn(TOOLING + f'stopped by signal {signal.SIGTERM.value}', out.getvalue())
        self.assertLess(time.monotonic() - started, 10)

    def test_a_signal_before_the_launch_skips_it_or_reaches_the_queue(self):
        launch = mock.Mock(side_effect=AssertionError('the queue launched after a stop'))
        with mock.patch.object(delete.subprocess, 'Popen', launch):
            self.queued_with_a_signal_during(('tempfile', 'TemporaryDirectory'))
        launch.assert_not_called()
        self.queued_with_a_signal_during(('subprocess', 'Popen'))

    def test_without_the_variable_private_env_supplies_the_hook_and_the_variable_wins(self):
        del self.env['NOTCHCAST_BUILD_QUEUE']
        self.assert_verdict(self.run_delete('Shots'), 1, BREACH)
        self.assertEqual(self.calls_made(), [])
        self.private_env(f'echo noise\nNOTCHCAST_BUILD_QUEUE="{self.hook}"\n')
        self.assert_verdict(self.run_delete('Shots'), 1, BREACH)
        self.assertEqual(self.calls_made(), [self.hold('--', 'Shots')])
        self.calls.write_text('')
        self.assert_verdict(self.run_delete('Shots', NOTCHCAST_BUILD_QUEUE=''), 1, BREACH)
        self.assertEqual(self.calls_made(), [])

    def test_a_private_env_that_fails_is_tooling_unless_already_in_a_slot(self):
        del self.env['NOTCHCAST_BUILD_QUEUE']
        for text in ('exit 1\n', f'set -e\nfalse\nNOTCHCAST_BUILD_QUEUE="{self.hook}"\n', 'false\n'):
            self.private_env(text)
            self.assert_verdict(self.run_delete('Shots'), 2, TOOLING + 'sourcing ')
        self.assert_verdict(self.run_delete('Shots', CHAD_BUILD_QUEUE_SLOT='2'), 1, BREACH)
        self.assertEqual(self.calls_made(), [])

    def scratch_dirs(self):
        return sorted(Path(self.env['NOTCHCAST_DELETE_SCRATCH']).glob('notchcast-delete.*'))

    def wait_for(self, ready):
        for _ in range(200):
            if ready():
                return
            time.sleep(0.05)
        self.fail('timed out')

    def test_a_signal_stops_the_step_tree_and_removes_the_scratch_dir(self):
        root = Path(self.tmp.name)
        write(root, 'bin/slow-xcodegen', '#!/bin/sh\nsleep 60 &\necho $! > "$STUB_PID"\nwait\n')
        (root / 'bin/slow-xcodegen').chmod(0o755)
        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            stub = root / 'stub.pid'
            stub.unlink(missing_ok=True)
            run = subprocess.Popen([sys.executable, str(SCRIPT), 'Keep'], cwd=self.repo, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env={**self.env, 'NOTCHCAST_BUILD_QUEUE': '', 'STUB_PID': str(stub),
                                        'XCODEGEN': str(root / 'bin/slow-xcodegen')})
            self.wait_for(lambda: stub.is_file() and stub.read_text().strip() and
                          any((path / 'owner.pid').is_file() for path in self.scratch_dirs()))
            self.assertEqual((self.scratch_dirs()[0] / 'owner.pid').read_text(), str(run.pid))
            sleeper = int(stub.read_text())
            run.send_signal(signum)
            stdout, stderr = run.communicate(timeout=30)
            self.assertEqual(run.returncode, 128 + signum, stdout + stderr)
            self.assertIn(TOOLING + f'stopped by signal {signum.value}', stdout)
            self.assertNotIn('Traceback', stdout + stderr)
            self.assertEqual(self.scratch_dirs(), [])
            self.wait_for(lambda: not alive(sleeper))

    def test_a_run_sweeps_dirs_of_dead_owners_and_old_pidless_ones_only(self):
        parent = Path(self.env['NOTCHCAST_DELETE_SCRATCH'])
        gone = subprocess.Popen(['true'])
        gone.wait()
        hour_ago = time.time() - 2 * 3600
        dirs = {}
        for name, pid, old in (('dead', gone.pid, False), ('live', os.getpid(), True), ('old', None, True),
                               ('fresh', None, False), ('garbled', 'x', True)):
            path = dirs[name] = parent / f'notchcast-delete.{name}'
            write(path, 'Keep/file', 'x')
            if pid is not None:
                (path / 'owner.pid').write_text(str(pid))
            if old:
                os.utime(path, (hour_ago, hour_ago))
        status = parent / 'notchcast-delete-status.old'
        status.mkdir()
        os.utime(status, (hour_ago, hour_ago))
        self.assert_verdict(self.run_delete('Keep', NOTCHCAST_BUILD_QUEUE=''), 0, 'PASS delete Keep')
        self.assertEqual(self.scratch_dirs(), sorted(dirs[name] for name in ('fresh', 'garbled', 'live')))
        self.assertTrue(status.is_dir())


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


if __name__ == '__main__':
    unittest.main()
