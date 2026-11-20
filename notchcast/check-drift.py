#!/usr/bin/env python3
"""Local fork-only drift gates."""
import argparse
from collections import Counter, defaultdict
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('swiftgraph', TOOLS / 'bin/swiftgraph.py')
swiftgraph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(swiftgraph)
KERNEL = {'Features/Notchcast'}
HUB = 'Tinycast/Features/Notchcast/Core/NotchcastFeature.swift'  # One line per feature until Phase 2b.
RULES = {'1': ('boundaries', 'core-lookups', 'upstream-folders'),
         '2': ('file-size',), '3': ('dead', 'test-only'), '4': ('clones', 'constants')}
WAIVER = re.compile(r'// drift: keep \S.*$')
IDENT = re.compile(r'[A-Za-z_]\w*')
DECL = re.compile(r'^[ \t]*((?:@\w+(?:\([^)\n]*\))?\s+)*)'
                  r'((?:(?:public|private|fileprivate|internal|final|nonisolated|static|class|'
                  r'mutating|override|indirect|convenience|required|lazy|weak)\s+)*)'
                  r'(class|struct|enum|protocol|actor|typealias|func|let|var)\s+`?([A-Za-z_]\w*)', re.M)
SKIP_ATTR = ('@objc', '@main', '@IBAction', '@NSApplicationMain', '@Environment', '@State',
             '@Binding', '@Bindable', '@AppStorage', '@propertyWrapper')
PATTERNS = {'try?': r'\btry\?', 'Task.sleep': r'\bTask\.sleep\b', 'Process()': r'\bProcess\s*\(\s*\)',
            'tool-paths': r'"/(?:usr/|bin/|sbin/|opt/)[^"\n]+"',
            'cancellation-loops': r'\bwhile\s+!Task\.isCancelled\b'}


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def config(root):
    return dict(re.findall(r'^(\w+)=([^\n]+)$', (root / 'notchcast/config.env').read_text(), re.M))


def upstream_base(root):
    exists = subprocess.run(['git', '-C', str(root), 'rev-parse', '-q', '--verify',
                             'refs/remotes/upstream/main'], capture_output=True)
    if exists.returncode:
        repo = config(root)['UPSTREAM_REPO']
        subprocess.run(['git', '-C', str(root), 'fetch', '-q', '--no-tags',
                        f'https://github.com/{repo}.git',
                        '+refs/heads/main:refs/remotes/upstream/main'], check=True)
    return git(root, 'merge-base', 'HEAD', 'refs/remotes/upstream/main')


def folder(path):
    parts = Path(path).parts
    if parts[0] == 'notchcast':
        return '/'.join(parts[:2])
    return '/'.join(parts[1:3]) if len(parts) > 3 and parts[1] == 'Features' else parts[1]


def unwaived(source):
    return '\n'.join('' if WAIVER.search(line) else line for line in source.split('\n'))


def sources(root, prefix):
    return {p.relative_to(root).as_posix(): p.read_text() for p in sorted((root / prefix).rglob('*.swift'))}


def jscpd():
    """jscpd from notchcast/jscpd's lockfile (every package's integrity hash), installed once per lockfile."""
    lock = TOOLS / 'jscpd/package-lock.json'
    cache = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'notchcast'
    home = cache / f'jscpd-{hashlib.sha256(lock.read_bytes()).hexdigest()[:16]}'
    binary = home / 'node_modules/.bin/jscpd'
    if binary.exists():
        return binary
    if not shutil.which('npm'):
        raise ValueError('gate 4 requires npm (Node 20+); duplicates were not checked')
    cache.mkdir(parents=True, exist_ok=True)
    work = tempfile.mkdtemp(prefix='jscpd.', dir=cache)
    try:
        for name in ('package.json', 'package-lock.json'):
            shutil.copy(TOOLS / 'jscpd' / name, work)
        result = subprocess.run(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=work,
                                capture_output=True, text=True, timeout=300)
        if result.returncode:
            raise ValueError(f'gate 4 jscpd install failed ({result.returncode}): {result.stderr.strip()}')
        with contextlib.suppress(OSError):  # a concurrent run installed the same lockfile first
            os.rename(work, home)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return binary


def clone_counts(root, files):
    binary = jscpd()
    with tempfile.TemporaryDirectory(prefix='drift-clones.') as work:
        work = Path(work).resolve()  # jscpd names files against real paths; macOS's $TMPDIR is a symlink
        tree, output = work / 'sources', work / 'report'
        tree.mkdir()
        for path, text in files.items():
            target = tree / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(unwaived(text))
        # npx --no runs only the installed jscpd, never fetching; main's fixture breaks npx to prove fail-closed.
        result = subprocess.run(['npx', '--no', '--', 'jscpd', '--min-tokens', '70', '--min-lines', '6',
                                 '--format', 'swift', '--reporters', 'json', '--silent',
                                 '--output', str(output), str(tree)], cwd=binary.parents[2],
                                capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise ValueError(f'gate 4 jscpd failed ({result.returncode}): {result.stderr.strip()}')
        if not (output / 'jscpd-report.json').exists():
            return {}  # jscpd 4 writes no report when no file reaches the token minimum
        report = json.loads((output / 'jscpd-report.json').read_text())
        counts = Counter()
        for clone in report['duplicates']:
            pair = []
            for side in ('firstFile', 'secondFile'):
                path = Path(clone[side]['name'])
                if not path.is_absolute():
                    path = binary.parents[2] / path  # relative to where jscpd ran, not to our caller
                pair.append(path.resolve().relative_to(tree).as_posix())
            if pair[0] != pair[1]:
                counts[' | '.join(sorted(pair))] += 1
        return dict(counts)


def measure(root, upstream, gates):
    prod = sources(root, 'Tinycast')
    tests = sources(root, 'Tests')
    added = set(git(root, 'diff', '--diff-filter=A', '--name-only', upstream, '--', '*.swift').splitlines())
    added.update(git(root, 'ls-files', '--others', '--exclude-standard', '--', '*.swift').splitlines())
    ours = {p: text for p, text in prod.items() if p in added}
    our_tests = {p: text for p, text in tests.items() if p in added}
    clean = {p: swiftgraph.strip_literals(unwaived(text)) for p, text in prod.items()}
    observed = {rule: {} for gate in gates for rule in RULES[gate]}
    if '1' in gates:
        with tempfile.TemporaryDirectory(prefix='drift-graph.') as work:
            with contextlib.redirect_stdout(io.StringIO()):
                swiftgraph.build(root, Path(work), 2, all_sources=True)
            graph = json.loads((Path(work) / 'graph.json').read_text())
        upstream_folders = {folder(p) for p in prod.keys() - ours.keys()}
        fork_folders = {folder(p) for p in ours} - upstream_folders
        pairs = defaultdict(set)
        for path in ours:
            origin = folder(path)
            if origin not in KERNEL:
                count = len(re.findall(r'\bNotchcastCore\.\w', clean[path]))
                if count:
                    observed['core-lookups'][path] = count
                if origin in upstream_folders:
                    observed['upstream-folders'][path] = 1
            if origin not in fork_folders or origin in KERNEL:
                continue
            names = set(IDENT.findall(clean[path]))
            for target in graph['file_adjacency'].get(path, []):
                dest = folder(target)
                declared = {d['name'] for d in graph['nodes'][target]['types'] if d['kind'] != 'extension'}
                if dest != origin and dest in fork_folders - KERNEL and names & declared:
                    pairs[f'{origin} -> {dest}'].add(path)
        observed['boundaries'] = {pair: len(paths) for pair, paths in pairs.items()}
    if '2' in gates:
        for path, text in (ours | our_tests).items():
            if path == HUB:
                continue
            length = len(text.splitlines())
            limit = 600 if path.startswith('Tests/') else 400
            if length > limit and not WAIVER.search(text.splitlines()[-1]):
                observed['file-size'][path] = length
    if '3' in gates:
        tokens = Counter(word for text in clean.values() for word in IDENT.findall(text))
        test_tokens = Counter(word for text in tests.values() for word in IDENT.findall(text))
        declarations = Counter(m[4] for text in clean.values() for m in DECL.finditer(text))
        for path in ours:
            for match in DECL.finditer(clean[path]):
                attrs, mods, kind, name = match.groups()
                if 'override' in mods or any(a in attrs for a in SKIP_ATTR):
                    continue
                if kind in ('func', 'let', 'var') and not {'static', 'class'} & set(mods.split()) and match.group().startswith((' ', '\t')):
                    continue
                if name in ('body', 'init', 'id', 'description', 'hash', 'main', 'makeBody', 'shared'):
                    continue
                if tokens[name] > declarations[name]:
                    continue
                rule = 'test-only' if test_tokens[name] else 'dead'
                observed[rule][f'{path}:{name}'] = 1
    if '4' in gates:
        observed['clones'] = clone_counts(root, ours)
        literals = defaultdict(set)
        for path, text in ours.items():
            text = unwaived(text)
            matches = list(re.finditer(r'(?<![\\#])"([a-z0-9][a-z0-9._/:-]{5,})"', text))
            marked = list(text)
            for match in matches:
                marked[match.start():match.end()] = 'D' + ' ' * (match.end() - match.start() - 1)
            visible = swiftgraph.strip_literals(''.join(marked))
            for match in matches:
                value = match[1]
                if not value.startswith(('app.notchcast', 'notchcast.', 'com.notchcast', 'com.apple.')):
                    continue
                if re.search(r'\b(?:systemName|systemImage)\s*:\s*$', text[:match.start()]):
                    continue
                if visible[match.start()] != 'D':
                    continue
                literals[value].add(folder(path))
        observed['constants'] = {key: len(owners) for key, owners in literals.items() if len(owners) > 1}
    return observed, ours


def check_counts(observed, baseline):
    problems = []
    for rule, counts in observed.items():
        allowed = baseline[rule]
        for key in sorted(counts.keys() | allowed.keys()):
            actual, limit = counts.get(key, 0), allowed.get(key, 0)
            if actual > limit:
                problems.append(f'{rule}: {key}: {actual} > {limit}')
            elif actual < limit:
                problems.append(f'{rule}: {key}: {actual} < {limit}; lower it in drift-baseline.json')
    return problems


def read_baseline(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'duplicate baseline key: {key}')
            result[key] = value
        return result
    baseline = json.loads(path.read_text(), object_pairs_hook=unique)
    expected = {rule for rules in RULES.values() for rule in rules} | {'alerts'}
    if baseline.keys() != expected:
        raise ValueError('baseline must contain exactly the gate rules and alerts')
    for rule, counts in baseline.items():
        if not isinstance(counts, dict) or any(type(v) is not int or v < 0 for v in counts.values()):
            raise ValueError(f'invalid baseline counts for {rule}')
    # shortcut: the ignored alerts counters stay in drift-baseline.json because branch v2/base's check-drift.py requires them; cut them once it does not.
    if not set(PATTERNS) <= baseline['alerts'].keys():
        raise ValueError('baseline alerts must define every pattern counter')
    return baseline


def compare_baseline(root, base, baseline):
    exists = subprocess.run(['git', '-C', str(root), 'cat-file', '-e',
                             f'{base}:notchcast/drift-baseline.json'], capture_output=True)
    if exists.returncode:
        git(root, 'rev-parse', '--verify', f'{base}^{{commit}}')
        return []
    with tempfile.TemporaryDirectory(prefix='drift-base.') as work:
        path = Path(work) / 'baseline.json'
        path.write_text(git(root, 'show', f'{base}:notchcast/drift-baseline.json'))
        previous = read_baseline(path)
    moved = {}  # A moved file keeps its budget: compare its `path` or `path:name` key under the old path.
    for line in git(root, 'diff', '-M', '--name-status', base).splitlines():
        status, _, paths = line.partition('\t')
        if status.startswith('R'):
            old, new = paths.split('\t')
            moved[new] = old
    def before(key):
        path, colon, name = key.partition(':')
        return moved.get(path, path) + colon + name
    return [f'{rule}: {key}: {value} > {previous[rule].get(before(key), 0)}'
            for rule, counts in baseline.items() for key, value in counts.items()
            if before(key) not in previous[rule] or value > previous[rule][before(key)]]


def pattern_counters(ours):
    return {(name, 'all'): sum(len(re.findall(pattern, text)) for text in ours.values())
            for name, pattern in PATTERNS.items()}


def main_counters(root, upstream):
    if subprocess.run(['git', '-C', str(root), 'rev-parse', '-q', '--verify', 'refs/remotes/origin/main'],
                      capture_output=True).returncode:
        return {}
    try:
        base = git(root, 'merge-base', 'HEAD', 'refs/remotes/origin/main')
        fork = git(root, 'merge-base', base, upstream)
    except subprocess.CalledProcessError:
        return {}
    added = set(git(root, 'diff', '--diff-filter=A', '--name-only', fork, base, '--', '*.swift').splitlines())
    with tempfile.TemporaryDirectory(prefix='drift-main.') as work:
        present = git(root, 'ls-tree', '--name-only', base, '--', 'Tinycast').split()
        archive = subprocess.run(['git', '-C', str(root), 'archive', base, *present],
                                 capture_output=True, check=True).stdout
        subprocess.run(['tar', '-x', '-C', work], input=archive, check=True)
        prod = {p: text for p, text in sources(Path(work), 'Tinycast').items()
                if p in added}
    return pattern_counters(prod)


def print_counters(observed, ours, baseline, known):
    print('Counter | Current | Baseline / threshold')
    for rule, counts in observed.items():
        print(f'{rule} | {sum(counts.values())} ({len(counts)} keys) | {sum(baseline[rule].values())}')
        for key, value in sorted(counts.items()):
            if value > baseline[rule].get(key, 0):
                print(f'GATE-THRESHOLD {rule}:{key.replace(" | ", "|")} {value} {baseline[rule].get(key, 0)}')
    breaches = []
    for (counter, key), value in sorted(pattern_counters(ours).items()):
        limit = baseline['alerts'][counter]
        print(f'{counter} | {value} | {limit} | {key}')
        if value > limit:
            mark = ' known' if value <= known.get((counter, key), limit) else ''
            print(f'GATE-THRESHOLD {counter} {value} {limit}{mark}')
            if not mark:
                breaches.append(f'threshold breach new or grown: {counter} {value} > {limit} '
                                f'(main: {known.get((counter, key), "none")})')
    return breaches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=TOOLS.parent)
    parser.add_argument('--upstream', help='Explicit upstream base, for isolated fixtures')
    parser.add_argument('--gates', default='1,2,3,4', choices=('1,2,3', '1,2,3,4', '1', '2', '3', '4'))
    parser.add_argument('--write-baseline', action='store_true', help='Seed or tighten the baseline; never raise existing budgets')
    parser.add_argument('--compare-base', help='Reject budget growth against this commit, without running tools')
    args = parser.parse_args()
    root = args.root.resolve()
    path = root / 'notchcast/drift-baseline.json'
    if args.compare_base:
        problems = compare_baseline(root, args.compare_base, read_baseline(path))
        print('\n'.join(problems) if problems else 'PASS: drift baseline did not grow')
        return bool(problems)
    if args.write_baseline and args.gates != '1,2,3,4':
        raise ValueError('writing the baseline requires all gates')
    upstream = args.upstream or upstream_base(root)
    observed, ours = measure(root, upstream, args.gates.split(','))
    if args.write_baseline:
        observed['alerts'] = {name: value for (name, _), value in pattern_counters(ours).items()}
        if path.exists():
            previous = read_baseline(path)
            observed['alerts'] = previous['alerts']
            if any(value > previous[rule].get(key, 0) for rule, counts in observed.items()
                   for key, value in counts.items()):
                raise ValueError('cannot raise or add baseline entries')
            for rule in observed.keys() - {'alerts'}:
                observed[rule] = {key: observed[rule].get(key, 0) for key in previous[rule] | observed[rule]}
        path.write_text(json.dumps(observed, indent=2, sort_keys=True) + '\n')
        print('Seeded drift-baseline.json')
        return 0
    baseline = read_baseline(path)
    problems = check_counts(observed, baseline)
    for gate in args.gates.split(','):
        count = sum(len(observed[r]) for r in RULES[gate])
        failed = any(p.split(':', 1)[0] in RULES[gate] for p in problems)
        print(f'gate {gate}: {"FAIL" if failed else "PASS"} ({count} keys)')
    for problem in problems:
        print(problem)
    if args.gates == '1,2,3,4':  # land.sh and local-ci.sh run all four; the pre-push subset stays quiet
        known = main_counters(root, upstream)
        breaches = print_counters(observed, ours, baseline, known)
        if known:
            print('\n'.join(breaches))
            problems += breaches
        elif breaches:
            print('WARN: origin/main counters unavailable; threshold breaches not enforced')
    return bool(problems)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f'drift: FAIL: {error}', file=sys.stderr)
        sys.exit(1)
