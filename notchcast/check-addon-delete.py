#!/usr/bin/env python3
"""Delete test for add-ons (notchcast/docs/addons.md §5): the app still builds and passes without one.

For each folder, in a scratch clone of the ref: delete Tinycast/Features/Notchcast/<Folder>/, its registry
line, its notchcast/licenses/borrowed.md lines and Tests/nc-<Folder>-*.swift, then regenerate the project,
build Debug and run Scripts/run-tests.sh.
Every surviving fork harness that notchcast/harness_inputs.py resolves in the scratch tree must report a result
in the run-tests log, so a harness the runner skipped cannot pass as clean.
Prints PASS per folder, or FAIL with the step and its log. A failure the deletion caused is a contract breach
(exit 1); one the tools caused (clone, xcodegen, timeout, a build that stopped without a Swift error) is a
tooling failure (exit 2). Standalone: ready-check does not run it.
Usage: check-addon-delete.py (<Folder> | --rotate | --all) [--ref HEAD]
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT_DIR = 'Tinycast/Features/Notchcast/'
REGISTRY = ROOT_DIR + 'NotchcastRegistry.swift'
BORROWED = 'notchcast/licenses/borrowed.md'
CORE_DIRS = {'Core', 'Hidden'}
ADDON_DECL = re.compile(r'\b(?:struct|enum|class)\s+(\w+)\b[^{]*\bNotchcastAddon\b')
SWIFT_ERROR = re.compile(r'\.swift:\d+:\d+: error:')
HARNESS_FAIL = re.compile(r'FAIL\S*\s+\S+')
ANSI = re.compile(r'\x1b\[[0-9;]*m')
RESULT_LINE = re.compile(r'^\[\d+/\d+\]\s+\S+\s+(\S+)', re.M)
LOGS = pathlib.Path.home() / 'Library/Caches/notchcast/addon-delete'
TIMEOUT = 3600


class Breach(Exception):
    pass


class Tooling(Exception):
    pass


def folders_at(tree):
    base = tree / ROOT_DIR
    return sorted(p.name for p in base.iterdir() if p.is_dir() and p.name not in CORE_DIRS) if base.is_dir() else []


def rotate_pick(folders, sha):
    return folders[int(sha, 16) % len(folders)]


def addon_types(folder_dir):
    return {match for path in folder_dir.rglob('*.swift') for match in ADDON_DECL.findall(path.read_text())}


def without_registry_lines(text, types):
    kept, removed = [], set()
    for line in text.splitlines(keepends=True):
        match = re.match(r'^\s*(\w+)\.self,\s*$', line)
        if match and match[1] in types:
            removed.add(match[1])
        else:
            kept.append(line)
    return ''.join(kept), removed


def delete_folder(tree, folder):
    folder_dir = tree / ROOT_DIR / folder
    types = addon_types(folder_dir)
    if not types:
        raise Tooling(f'{folder}: no type declared `: NotchcastAddon`')
    registry = tree / REGISTRY
    text, removed = without_registry_lines(registry.read_text(), types)
    if removed != types:
        raise Breach(f"{folder}: registry has no line for {', '.join(sorted(types - removed))}")
    registry.write_text(text)
    shutil.rmtree(folder_dir)
    for test in (tree / 'Tests').glob(f'nc-{folder}-*.swift'):
        test.unlink()
    borrowed = tree / BORROWED
    if borrowed.is_file():
        lines = borrowed.read_text().splitlines(keepends=True)
        borrowed.write_text(''.join(line for line in lines if not line.startswith(f'{folder}: ')))
    table = f'Notchcast{folder}'
    orphans = [str(p.relative_to(tree)) for p in (tree / 'Tinycast').rglob('*.swift')
               if f'table: "{table}"' in p.read_text()]
    if orphans:
        raise Breach(f"strings of table {table} remain in {', '.join(orphans)}")


def step(name, command, tree, log, env):
    try:
        with open(log, 'w') as out:
            code = subprocess.run(command, cwd=tree, stdout=out, stderr=subprocess.STDOUT, env=env,
                                  timeout=TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        raise Tooling(f'{name} timed out after {TIMEOUT}s; log: {log}')
    except OSError as error:
        raise Tooling(f'{name} could not start ({error}); log: {log}')
    if code == 0:
        return
    text = log.read_text(errors='replace')
    if name == 'xcodegen':
        raise Tooling(f'xcodegen failed; log: {log}')
    if name == 'build' and SWIFT_ERROR.search(text) or name == 'run-tests' and HARNESS_FAIL.search(text):
        raise Breach(f'{name} failed; log: {log}')
    raise Tooling(f'{name} failed without a Swift error or harness failure; log: {log}')


def fork_harnesses(tree, env):
    try:
        listing = subprocess.run([sys.executable, 'notchcast/harness_inputs.py'], cwd=tree, env=env, text=True,
                                 capture_output=True, check=True).stdout
    except subprocess.CalledProcessError as error:
        raise Tooling(f'harness_inputs.py failed: {error.stderr.strip()}')
    names = (pathlib.Path(line.split('\t', 1)[0]).stem for line in listing.splitlines() if line)
    return sorted(name for name in names if name.startswith(('nc-', 'notchcast-')))


def unreported(log_text, names):
    reported = set(RESULT_LINE.findall(ANSI.sub('', log_text)))
    return [name for name in names if name not in reported]


def check(repo, sha, folder, scratch):
    tree = scratch / folder
    log_prefix = LOGS / f'{sha[:12]}-{folder}'
    try:
        subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout', '--no-tags', str(repo), str(tree)],
                       check=True, capture_output=True)
        subprocess.run(['git', '-C', str(tree), 'checkout', '--quiet', '--detach', sha], check=True, capture_output=True)
    except subprocess.CalledProcessError as error:
        raise Tooling(f'clone failed: {error.stderr.decode().strip()}')
    delete_folder(tree, folder)
    tmp = scratch / f'{folder}-tmp'
    tmp.mkdir()
    env = dict(os.environ, TMPDIR=str(tmp))
    xcodegen = os.environ.get('XCODEGEN') or shutil.which('xcodegen') or 'xcodegen'
    step('xcodegen', [xcodegen, 'generate', '--quiet'], tree, pathlib.Path(f'{log_prefix}-xcodegen.log'), env)
    step('build', ['xcodebuild', '-project', 'Tinycast.xcodeproj', '-scheme', 'Tinycast', '-configuration', 'Debug',
                   '-jobs', os.environ.get('CHAD_BUILD_QUEUE_JOBS', '4'), '-derivedDataPath', str(tmp / 'dd'),
                   'CODE_SIGNING_ALLOWED=NO', 'build', '-quiet'], tree, pathlib.Path(f'{log_prefix}-build.log'), env)
    harnesses = fork_harnesses(tree, env)
    log = pathlib.Path(f'{log_prefix}-run-tests.log')
    step('run-tests', ['./Scripts/run-tests.sh'], tree, log, env)
    if missing := unreported(log.read_text(errors='replace'), harnesses):
        raise Tooling(f"run-tests reported no result for fork harnesses {', '.join(missing)}; log: {log}")


def main():
    parser = argparse.ArgumentParser()
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument('folder', nargs='?')
    target.add_argument('--rotate', action='store_true')
    target.add_argument('--all', action='store_true')
    parser.add_argument('--ref', default='HEAD')
    args = parser.parse_args()
    repo = pathlib.Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
    sha = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', args.ref], text=True).strip()
    listing = subprocess.check_output(['git', '-C', str(repo), 'ls-tree', '-d', '--name-only', f'{sha}:{ROOT_DIR}'],
                                      text=True).split()
    folders = sorted(set(listing) - CORE_DIRS)
    if not folders:
        print(f'no add-on folders at {sha[:12]}; nothing to delete')
        return 0
    if args.folder and args.folder not in folders:
        print(f"no add-on folder {args.folder} at {sha[:12]} (folders: {', '.join(folders)})", file=sys.stderr)
        return 2
    picked = folders if args.all else [rotate_pick(folders, sha)] if args.rotate else [args.folder]
    LOGS.mkdir(parents=True, exist_ok=True)
    status = 0
    # Debug builds embed absolute source paths, so build outside the home as ready-check does.
    with tempfile.TemporaryDirectory(dir=os.environ.get('NOTCHCAST_DELETE_SCRATCH') or
                                     subprocess.check_output(['getconf', 'DARWIN_USER_TEMP_DIR'], text=True).strip(),
                                     prefix='notchcast-delete.') as scratch:
        for folder in picked:
            try:
                check(repo, sha, folder, pathlib.Path(scratch))
                print(f'PASS delete {folder} at {sha[:12]}: xcodegen, build, run-tests')
            except Breach as error:
                print(f'FAIL delete {folder} at {sha[:12]}: contract breach: {error}')
                status = 1
            except Tooling as error:
                print(f'FAIL delete {folder} at {sha[:12]}: tooling failure, not a contract breach: {error}')
                status = status or 2
    return status


if __name__ == '__main__':
    sys.exit(main())
