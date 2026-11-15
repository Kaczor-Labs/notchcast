#!/usr/bin/env python3
"""Gate the add-on system's upstream footprint and its folder boundaries (notchcast/docs/addons.md §3, §5).

The caller names the mode (ci-build.sh derives it from the branch name). Core mode (v2/addons-core[-<n>]): the
upstream paths the branch changes against the base stay within notchcast/addons-budget.env. Feature mode
(v2/addons-<feature>): the branch owns the folders that declare the types its added registry lines name (or,
with no added line, the one folder it touches), and every changed path is inside an owned folder, an owned
Tests/nc-<Folder>-*.swift, a `<Type>.self,` line in the registry, or an appended notchcast/licenses/borrowed.md
line that starts with an owned folder. Mode none runs only the reference guard,
which on every branch fails when a line the fork added outside an add-on's folder names that add-on's switch
ids or command slugs, or names one of its top-level types in code rather than in a string or comment (registry
line and dependency arrays excepted).
Exit 1 is a contract breach, exit 2 a tooling failure.
Usage: check-addons.py --mode (core|feature|none) --base <ref> [--head <ref>] [--upstream <ref>]
"""
import argparse
import pathlib
import re
import subprocess
import sys

ROOT_DIR = 'Tinycast/Features/Notchcast/'
REGISTRY = ROOT_DIR + 'NotchcastRegistry.swift'
CORE_DIRS = {'Core', 'Hidden'}
# Core's harnesses pin the frozen contract ids and never reach add-on code.
GUARD_EXEMPT = re.compile(r'^Tests/nc-Notchcast-[^/]*\.swift$')
REGISTRY_LINE = re.compile(r'^\s*(\w+)\.self,\s*$')
BORROWED = 'notchcast/licenses/borrowed.md'
BORROWED_LINE = re.compile(r'^(\w+): \S+ ← \S+/\S+ \([^)]+\)$')
SWITCH_ID = re.compile(r'NotchcastSwitch\(\s*id:\s*"([^"]+)"')
SLUG = re.compile(r'\bslug:\s*"([^"]+)"')
TYPE_DECL = re.compile(r'^(?:@\w+\s+)*(?:(?:public|internal|final|nonisolated)\s+)*'
                       r'(?:struct|class|enum|protocol|actor|typealias)\s+(\w+)', re.M)
ADDON_DECL = re.compile(r'\b(?:struct|enum|class)\s+(\w+)\b[^{]*\bNotchcastAddon\b')
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


def registry_changes(root, base, head):
    added, problems = [], []
    for line in git('diff', '-U0', f'{base}...{head}', '--', REGISTRY, root=root).splitlines():
        if line.startswith(('+++', '---', '@@')) or not line[:1] in '+-':
            continue
        match = REGISTRY_LINE.match(line[1:])
        if not match:
            problems.append(f'{REGISTRY}: "{line[1:].strip()}" is not a `<Type>.self,` registry line')
        elif line[0] == '+':
            added.append(match[1])
    return added, problems


def borrowed_changes(root, base, head, owned):
    problems = []
    for line in git('diff', '-U0', f'{base}...{head}', '--', BORROWED, root=root).splitlines():
        if line.startswith(('+++', '---', '@@')) or line[:1] not in ('+', '-'):
            continue
        match = BORROWED_LINE.match(line[1:])
        if line[0] == '-':
            problems.append(f'{BORROWED}: removes "{line[1:].strip()}"; a feature branch only appends its lines')
        elif not match or match[1] not in owned:
            problems.append(f'{BORROWED}: "{line[1:].strip()}" is not a '
                            f'`<owned folder>: <our file> ← <repo>/<file> (<licence>)` line')
    return problems


def feature_gate(root, base, head, changed):
    added, problems = registry_changes(root, base, head) if REGISTRY in changed else ([], [])
    declared = {t: f for f in addon_folders(root) for text in folder_sources(root, f).values()
                for t in ADDON_DECL.findall(text)}
    owned = {declared[t] for t in added if t in declared}
    for t in added:
        if t not in declared:
            problems.append(f'{REGISTRY}: {t} is not declared `: NotchcastAddon` in any add-on folder')
    touched = sorted({f for f in map(folder_of, changed) if f})
    if not added and len(touched) == 1:
        owned = set(touched)
    folders = sorted(owned)
    if BORROWED in changed:
        problems += borrowed_changes(root, base, head, owned)
    for path in changed:
        if path in (REGISTRY, BORROWED) or folder_of(path) in owned:
            continue
        if any(path.startswith(f'Tests/nc-{f}-') and path.endswith('.swift') for f in folders):
            continue
        problems.append(f'{path}: outside the add-on folders {folders or "(none)"}; '
                        'a feature branch touches only its folders, its tests and one registry line')
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


def swift_masks(text):
    """Two copies of Swift source, newlines kept: comments blanked, and comments plus string contents blanked."""
    bare, code = [], []
    stack, i, n = ['code'], 0, len(text)

    def emit(chunk, in_string=False, in_comment=False):
        blank = re.sub(r'[^\n]', ' ', chunk)
        bare.append(blank if in_comment else chunk)
        code.append(blank if in_comment or in_string else chunk)

    while i < n:
        state = stack[-1]
        if state == 'block':
            if text.startswith('/*', i):
                stack.append('block')
                emit('/*', in_comment=True)
                i += 2
            elif text.startswith('*/', i):
                stack.pop()
                emit('*/', in_comment=True)
                i += 2
            else:
                emit(text[i], in_comment=True)
                i += 1
        elif isinstance(state, tuple):
            hashes, triple = state
            close = ('"""' if triple else '"') + '#' * hashes
            if text.startswith(close, i):
                stack.pop()
                emit(close, in_string=True)
                i += len(close)
            elif text.startswith('\\' + '#' * hashes + '(', i):
                opener = '\\' + '#' * hashes + '('
                stack.append(0)
                emit(opener, in_string=True)
                i += len(opener)
            elif text[i] == '\\' and not hashes:
                emit(text[i:i + 2], in_string=True)
                i += 2
            else:
                emit(text[i], in_string=True)
                i += 1
        else:
            interpolation = isinstance(state, int)
            match = re.compile(r'(#*)("""|")').match(text, i)
            if text.startswith('//', i):
                end = text.find('\n', i)
                end = n if end < 0 else end
                emit(text[i:end], in_comment=True)
                i = end
            elif text.startswith('/*', i):
                stack.append('block')
                emit('/*', in_comment=True)
                i += 2
            elif match:
                stack.append((len(match[1]), match[2] == '"""'))
                emit(match[0], in_string=True)
                i = match.end()
            elif interpolation and text[i] == '(':
                stack[-1] += 1
                emit('(')
                i += 1
            elif interpolation and text[i] == ')':
                if state == 0:
                    stack.pop()
                    emit(')', in_string=True)
                else:
                    stack[-1] -= 1
                    emit(')')
                i += 1
            else:
                emit(text[i])
                i += 1
    return ''.join(bare), ''.join(code)


def guard(root, upstream, head):
    tokens = {}
    for folder in addon_folders(root):
        text = '\n'.join(folder_sources(root, folder).values())
        ids = set(SWITCH_ID.findall(text))
        slugs = set(SLUG.findall(text))
        types = set(TYPE_DECL.findall(swift_masks(text)[1]))
        literals = [rf'"{re.escape(i)}"' for i in ids] + [rf'"[^"]*\bnc-{re.escape(s)}\b[^"]*"' for s in slugs]
        tokens[folder] = (re.compile('|'.join(literals)) if literals else None,
                          re.compile('|'.join(rf'\b{re.escape(t)}\b' for t in types)) if types else None)
    problems, masks = [], {}
    for path, lineno, _ in fork_added_lines(root, upstream, head):
        if GUARD_EXEMPT.match(path):
            continue
        if path not in masks:
            masks[path] = [m.splitlines() for m in swift_masks(git('show', f'{head}:{path}', root=root))]
        bare, code = (lines[lineno - 1] for lines in masks[path])
        own = folder_of(path)
        if path == REGISTRY and REGISTRY_LINE.match(code):
            continue
        if own:
            bare = DEPENDENCIES.sub('', bare)
        for folder, (literal, identifier) in tokens.items():
            if folder == own or path.startswith(f'Tests/nc-{folder}-'):
                continue
            hit = (literal and literal.search(bare)) or (identifier and identifier.search(code))
            if hit:
                problems.append(f'{path}:{lineno}: names {folder}\'s {hit[0]} outside its folder')
    return problems


def run(root, base, head, upstream, mode):
    changed = [p for p in git('diff', '--name-only', f'{base}...{head}', root=root).splitlines() if p]
    if mode == 'core':
        problems, summary = core_gate(root, base, head, upstream, changed)
    elif mode == 'feature':
        problems, summary = feature_gate(root, base, head, changed)
    else:
        problems, summary = [], 'no add-on gate'
    problems += guard(root, upstream, head)
    print(f'add-on gate ({mode}): {summary}')
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', required=True, choices=('core', 'feature', 'none'))
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--upstream', default=None)
    parser.add_argument('--root', default=str(pathlib.Path(__file__).resolve().parent.parent))
    args = parser.parse_args()
    try:
        upstream = args.upstream or git('merge-base', args.head, 'refs/remotes/upstream/main', root=args.root).strip()
        problems = run(args.root, args.base, args.head, upstream, args.mode)
    except (Tooling, OSError, ValueError) as error:
        print(f'add-on gate: tooling failure, not a contract breach: {error}', file=sys.stderr)
        return 2
    for problem in problems:
        print(f'::error::{problem}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
