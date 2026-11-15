#!/usr/bin/env python3
"""Gate the add-on system's upstream footprint and its folder boundaries (notchcast/docs/addons.md §3, §5).

Core mode (the branch changes Notchcast/Core, a root Core file or the budget): the upstream paths it changes
against the base stay within notchcast/addons-budget.env. Feature mode (it changes only add-on folders or the
registry): every changed path is inside its own folders, its own Tests/nc-<Folder>-*.swift, or a `<Type>.self,`
line in the registry. On every branch the reference guard fails when a line the fork added outside an add-on's
folder names that add-on's switch ids, command slugs or types (registry line and dependency arrays excepted).
Exit 1 is a contract breach, exit 2 a tooling failure.
Usage: check-addons.py --base <ref> [--head <ref>] [--upstream <ref>]
"""
import argparse
import pathlib
import re
import subprocess
import sys

ROOT_DIR = 'Tinycast/Features/Notchcast/'
REGISTRY = ROOT_DIR + 'NotchcastRegistry.swift'
CORE_DIRS = {'Core', 'Hidden'}
CORE_FILES = {ROOT_DIR + 'NotchcastCore.swift', ROOT_DIR + 'NotchcastSettingsPane.swift',
              'notchcast/addons-budget.env'}
# Core's harnesses pin the frozen contract ids and never reach add-on code.
GUARD_EXEMPT = re.compile(r'^Tests/nc-Notchcast-[^/]*\.swift$')
REGISTRY_LINE = re.compile(r'^\s*(\w+)\.self,\s*$')
SWITCH_ID = re.compile(r'NotchcastSwitch\(\s*id:\s*"([^"]+)"')
SLUG = re.compile(r'\bslug:\s*"([^"]+)"')
TYPE_DECL = re.compile(r'^\s*(?:@\w+\s+)*(?:(?:public|internal|final|nonisolated)\s+)*'
                       r'(?:struct|class|enum|protocol|actor|typealias)\s+(\w+)', re.M)
ADDON_DECL = r'\b(?:struct|enum|class)\s+{}\b[^{{]*\bNotchcastAddon\b'
DEPENDENCIES = re.compile(r'dependencies:\s*\[[^\]]*\]')


class Tooling(Exception):
    pass


def git(*args, root):
    result = subprocess.run(['git', *args], cwd=root, capture_output=True, text=True)
    if result.returncode != 0:
        raise Tooling(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def folder_of(path):
    if not path.startswith(ROOT_DIR):
        return None
    parts = path[len(ROOT_DIR):].split('/')
    return parts[0] if len(parts) > 1 and parts[0] not in CORE_DIRS else None


def addon_folders(root):
    base = pathlib.Path(root) / ROOT_DIR
    return sorted(p.name for p in base.iterdir() if p.is_dir() and p.name not in CORE_DIRS) if base.is_dir() else []


def folder_sources(root, folder):
    return {str(p.relative_to(root)): p.read_text() for p in sorted((pathlib.Path(root) / ROOT_DIR / folder).rglob('*.swift'))}


def numstat(root, base, head, paths):
    if not paths:
        return []
    rows = []
    for line in git('diff', '--numstat', f'{base}...{head}', '--', *paths, root=root).splitlines():
        plus, minus, path = line.split('\t', 2)
        rows.append((int(plus) if plus != '-' else 0, int(minus) if minus != '-' else 0, path))
    return rows


def read_budget(root):
    budget = {}
    for line in (pathlib.Path(root) / 'notchcast/addons-budget.env').read_text().splitlines():
        if line.strip() and not line.lstrip().startswith('#'):
            key, _, value = line.partition('=')
            budget[key.strip()] = int(value.strip())
    missing = {'FILES', 'PLUS', 'MINUS'} - budget.keys()
    if missing:
        raise Tooling(f"addons-budget.env lacks {', '.join(sorted(missing))}")
    return budget


def core_gate(root, base, head, upstream, changed):
    upstream_paths = set(git('ls-tree', '-r', '--name-only', upstream, root=root).splitlines())
    rows = numstat(root, base, head, sorted(p for p in changed if p in upstream_paths))
    files, plus, minus = len(rows), sum(r[0] for r in rows), sum(r[1] for r in rows)
    budget = read_budget(root)
    for p, m, path in rows:
        print(f'  {path} +{p} -{m}')
    line = (f'upstream touch: {files} files, +{plus} -{minus} '
            f"(budget {budget['FILES']} files, +{budget['PLUS']} -{budget['MINUS']})")
    over = files > budget['FILES'] or plus > budget['PLUS'] or minus > budget['MINUS']
    return [f'{line}: over budget; raise notchcast/addons-budget.env with the reason'] if over else [], line


def feature_gate(root, base, head, changed):
    folders = sorted({f for f in map(folder_of, changed) if f})
    problems = []
    for path in changed:
        if folder_of(path) or path == REGISTRY:
            continue
        if any(path.startswith(f'Tests/nc-{f}-') and path.endswith('.swift') for f in folders):
            continue
        problems.append(f'{path}: outside the add-on folders {folders or "(none)"}; '
                        'a feature branch touches only its folders, its tests and one registry line')
    if REGISTRY in changed:
        diff = git('diff', '-U0', f'{base}...{head}', '--', REGISTRY, root=root)
        for line in diff.splitlines():
            if line.startswith(('+++', '---', '@@')) or not line[:1] in '+-':
                continue
            match = REGISTRY_LINE.match(line[1:])
            if not match:
                problems.append(f'{REGISTRY}: "{line[1:].strip()}" is not a `<Type>.self,` registry line')
            elif line[0] == '+' and not any(re.search(ADDON_DECL.format(match[1]), text)
                                            for f in folders for text in folder_sources(root, f).values()):
                problems.append(f'{REGISTRY}: {match[1]} is not declared `: NotchcastAddon` in {folders or "(none)"}')
    return problems, f"feature folders: {', '.join(folders) or '(none)'}"


def fork_added_lines(root, upstream, head):
    diff = git('diff', '-U0', '--no-color', f'{upstream}...{head}', '--', 'Tinycast', 'Tests', root=root)
    path, lineno = None, 0
    for line in diff.splitlines():
        if line.startswith('+++ '):
            path = line[6:] if line.startswith('+++ b/') else None
        elif line.startswith('@@'):
            lineno = int(re.search(r'\+(\d+)', line)[1])
        elif line.startswith('+') and path and path.endswith('.swift'):
            yield path, lineno, line[1:]
            lineno += 1


def guard(root, upstream, head):
    tokens = {}
    for folder in addon_folders(root):
        text = '\n'.join(folder_sources(root, folder).values())
        ids = set(SWITCH_ID.findall(text))
        slugs = set(SLUG.findall(text))
        types = set(TYPE_DECL.findall(text))
        tokens[folder] = (re.compile('|'.join(
            [rf'"{re.escape(i)}"' for i in ids] + [rf'"[^"]*\bnc-{re.escape(s)}\b[^"]*"' for s in slugs]
            + [rf'\b{re.escape(t)}\b' for t in types])) if ids or slugs or types else None)
    problems = []
    for path, lineno, line in fork_added_lines(root, upstream, head):
        if GUARD_EXEMPT.match(path):
            continue
        own = folder_of(path)
        if path == REGISTRY and REGISTRY_LINE.match(line):
            continue
        scanned = DEPENDENCIES.sub('', line) if own else line
        for folder, pattern in tokens.items():
            if folder == own or path.startswith(f'Tests/nc-{folder}-') or not pattern:
                continue
            hit = pattern.search(scanned)
            if hit:
                problems.append(f'{path}:{lineno}: names {folder}\'s {hit[0]} outside its folder')
    return problems


def run(root, base, head, upstream):
    changed = [p for p in git('diff', '--name-only', f'{base}...{head}', root=root).splitlines() if p]
    if any(p.startswith(ROOT_DIR + 'Core/') or p in CORE_FILES for p in changed):
        problems, summary = core_gate(root, base, head, upstream, changed)
        mode = 'core'
    elif any(folder_of(p) or p == REGISTRY for p in changed):
        problems, summary = feature_gate(root, base, head, changed)
        mode = 'feature'
    else:
        problems, summary, mode = [], 'no add-on change', 'none'
    problems += guard(root, upstream, head)
    print(f'add-on gate ({mode}): {summary}')
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--upstream', default=None)
    parser.add_argument('--root', default=str(pathlib.Path(__file__).resolve().parent.parent))
    args = parser.parse_args()
    try:
        upstream = args.upstream or git('merge-base', args.head, 'refs/remotes/upstream/main', root=args.root).strip()
        problems = run(args.root, args.base, args.head, upstream)
    except (Tooling, OSError, ValueError) as error:
        print(f'add-on gate: tooling failure, not a contract breach: {error}', file=sys.stderr)
        return 2
    for problem in problems:
        print(f'::error::{problem}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
