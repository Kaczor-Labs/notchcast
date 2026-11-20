#!/bin/bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=notchcast/config.env
source notchcast/config.env
export CI_SKIP_TESTS HIDDEN_TESTS LINUX_OK_TESTS LINUX_DENY_INPUTS
python3 - "$@" <<'PY'
import fnmatch
import os
import subprocess
import sys

sys.path.insert(0, 'notchcast')
from harness_inputs import harnesses

args = sys.argv[1:]
files = {}
while len(args) > 1 and args[0] in ('--unsure', '--linux'):
    files[args[0]] = args[1]
    args = args[2:]
unsure, linux = files.get('--unsure'), files.get('--linux')
if len(args) != 2:
    sys.exit('usage: changed-harnesses.sh [--unsure <absolute file>] [--linux <absolute file>] <base> <head>')
base, head = args
# --no-renames lists both ends of a move; a moved source leaves the harness that compiled it.
changed = set(subprocess.check_output(
    ['git', 'diff', '--name-only', '--no-renames', '-z', base, head], text=True).split('\0')) - {''}
selected = {'notchcast-hidden-features-test'}
matched = set()
reached = set()
for path, inputs in harnesses():
    name = path.stem
    patterns = inputs.patterns + inputs.reads
    # Against the changed paths, not the tree: a deleted source no longer exists to glob.
    hits = {file for file in changed
            if file == str(path) or any(fnmatch.fnmatchcase(file, pattern) for pattern in patterns)}
    if hits:
        selected.add(name)
        reached.add(name)
        matched |= hits
reasons = []
if unsure or linux:
    # The selector never judges itself: changing what selects or runs harnesses runs them all.
    runner = {'notchcast/changed-harnesses.sh', 'notchcast/harness_inputs.py', 'notchcast/command-harness-sources.sh',
              'notchcast/test-harnesses.sh', 'notchcast/ci-tests.sh', 'notchcast/config.env', 'notchcast/lanes.py',
              'Scripts/run-tests.sh', 'project.yml', '.github/workflows/pr.yml'}
    reasons = [f'runner: {file}' for file in sorted(changed)
               if file in runner or file.startswith('notchcast/actions/tests/')]
    # Shared code reaches harnesses through sources a header may not list yet: run them all.
    shared = ('Tinycast/DesignSystem/', 'Tinycast/Platform/', 'Tinycast/Features/Notchcast/Core/', 'Tests/Kit/')
    reasons += [f'shared: {file}' for file in sorted(changed) if file.startswith(shared)]
    from lanes import build_closure, needs_build
    closure = build_closure(head, changed)
    # A path the build reaches but no harness names may still compile into one: run them all.
    reasons += [f'unmapped: {file}' for file in sorted(changed - matched)
                if needs_build(file, closure) and not {f'runner: {file}', f'shared: {file}'} & set(reasons)]
if unsure:
    with open(unsure, 'w') as out:
        out.writelines(reason + '\n' for reason in reasons)
hidden = set(os.environ.get('HIDDEN_TESTS', '').split())
if linux:
    # Why this diff cannot land from Linux; empty when every harness it reaches is linux-ok and the selection is sure.
    # The always-run harness counts only when the diff reaches its inputs: untouched, it cannot change its verdict.
    mac_only = sorted(reached - hidden - set(os.environ.get('LINUX_OK_TESTS', '').split()))
    denied = os.environ.get('LINUX_DENY_INPUTS', '').split()
    with open(linux, 'w') as out:
        out.writelines(f'mac-only: {name}\n' for name in mac_only)
        out.writelines(f'denied: {file}\n' for file in sorted(changed)
                       if any(fnmatch.fnmatchcase(file, pattern) for pattern in denied))
        # Unmapped paths do not count: a Mac landing runs nothing more for them either.
        out.writelines(reason + '\n' for reason in reasons if reason.startswith('runner: '))
# Selection keeps CI_SKIP_TESTS harnesses: the shard runner drops them only on a hosted VM.
print('\n'.join(sorted((selected | {'notchcast-hidden-features-test'}) - hidden)))
PY
