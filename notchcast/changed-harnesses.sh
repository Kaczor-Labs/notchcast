#!/bin/bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=notchcast/config.env
source notchcast/config.env
export CI_SKIP_TESTS HIDDEN_TESTS
python3 - "$@" <<'PY'
import fnmatch
import os
import subprocess
import sys

sys.path.insert(0, 'notchcast')
from harness_inputs import harnesses

args = sys.argv[1:]
unsure = args[1] if args[:1] == ['--unsure'] and len(args) > 1 else None
args = args[2:] if unsure else args
if len(args) != 2:
    sys.exit('usage: changed-harnesses.sh [--unsure <absolute file>] <base> <head>')
base, head = args
# --no-renames lists both ends of a move; a moved source leaves the harness that compiled it.
changed = set(subprocess.check_output(
    ['git', 'diff', '--name-only', '--no-renames', '-z', base, head], text=True).split('\0')) - {''}
selected = {'notchcast-hidden-features-test'}
matched = set()
for path, inputs in harnesses():
    name = path.stem
    patterns = inputs.patterns + inputs.reads
    # Against the changed paths, not the tree: a deleted source no longer exists to glob.
    hits = {file for file in changed
            if file == str(path) or any(fnmatch.fnmatchcase(file, pattern) for pattern in patterns)}
    if hits:
        selected.add(name)
        matched |= hits
if unsure:
    # The selector never judges itself: changing what selects or runs harnesses runs them all.
    runner = {'notchcast/changed-harnesses.sh', 'notchcast/harness_inputs.py', 'notchcast/command-harness-sources.sh',
              'notchcast/test-harnesses.sh', 'notchcast/ci-tests.sh', 'notchcast/config.env', 'notchcast/lanes.py',
              'Scripts/run-tests.sh', 'project.yml', '.github/workflows/pr.yml'}
    reasons = [f'runner: {file}' for file in sorted(changed)
               if file in runner or file.startswith('notchcast/actions/tests/')]
    from lanes import build_closure, needs_build
    closure = build_closure(head, changed)
    # A path the build reaches but no harness names may still compile into one: run them all.
    reasons += [f'unmapped: {file}' for file in sorted(changed - matched)
                if needs_build(file, closure) and f'runner: {file}' not in reasons]
    with open(unsure, 'w') as out:
        out.writelines(reason + '\n' for reason in reasons)
# Selection keeps CI_SKIP_TESTS harnesses: the shard runner drops them only on a hosted VM.
hidden = set(os.environ.get('HIDDEN_TESTS', '').split())
print('\n'.join(sorted((selected | {'notchcast-hidden-features-test'}) - hidden)))
PY
