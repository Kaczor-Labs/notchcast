#!/usr/bin/env python3
"""Gate the add-on system's upstream footprint and its folder boundaries (notchcast/docs/addons.md §3, §5).

The caller names the mode, or passes --branch to derive it (ci-checks.sh does): core by name, feature for any other
v2/addons-* or a branch that adds an add-on or touches one add-on's folder, else none. Core mode: the
upstream paths the branch changes against the base stay within notchcast/addons-budget.env. Feature mode
(v2/addons-<feature>): the branch owns the folders whose add-on file gains its `// notchcast-addon-order:` line
(or, with none, the one folder it touches), and every changed path is inside an owned folder, an owned
Tests/nc-<Folder>-*.swift or an owned notchcast/licenses/borrowed/<Folder>.txt. Every mode runs two guards. The
shared-list guard fails a hand edit of a list made from the add-ons' own files: the generated registry, an entry
in notchcast/licenses/borrowed.md, a phrase on a README tab line, a fork harness named in a config.env harness list.
The reference guard fails when a line the fork added outside an add-on's folder names that add-on's switch
ids or command slugs, or names one of its top-level non-private types as a code identifier, never in a string or
comment (registry line and dependency arrays excepted).
Exit 1 is a contract breach, exit 2 a tooling failure.
Usage: check-addons.py (--mode (core|feature|none) | --branch <name>) --base <ref> [--head <ref>] [--upstream <ref>]
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
BORROWED_DIR = 'notchcast/licenses/borrowed/'
BORROWED_LINE = re.compile(r'^(\w+): \S+ ← \S+/\S+ \([^)]+\)$')
# Any entry shape, so a line the strict pattern misses still fails; the header is prose.
CREDIT_LIKE = re.compile(r'^\s*`?[\w-]+`?:\s')
ORDER_LINE = re.compile(r'^// notchcast-addon-order:')
# A branch that changes the generator may rewrite what it generates.
GENERATOR = 'notchcast/addons.py'
README_PUBLIC = 'notchcast/README.public.md'
TABS = ('<!-- addon-tabs:start -->', '<!-- addon-tabs:end -->')
TAB_LINE = re.compile(r'^  - \*\*(.+?)\*\*:(.*)$')
CONFIG = 'notchcast/config.env'
FORK_HARNESS = re.compile(r'(?<![\w./-])((?:nc|notchcast)-[\w+-]*-test)\b')
SWITCH_ID = re.compile(r'NotchcastSwitch\(\s*id:\s*"([^"]+)"')
SLUG = re.compile(r'\bslug:\s*"([^"]+)"')
# Column 0 and no private/fileprivate: only a type another folder could name in code.
TYPE_DECL = re.compile(r'^(?:@\w+\s+)*(?:(?:open|public|package|internal|final|nonisolated)\s+)*'
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


def added_lines(root, base, head, path):
    """(head line number, text) of each line the branch adds to path."""
    lineno = 0
    for line in git('diff', '-U0', '--no-color', f'{base}...{head}', '--', path, root=root).splitlines():
        if line.startswith('@@'):
            lineno = int(re.search(r'\+(\d+)', line)[1])
        elif line.startswith('+') and not line.startswith('+++'):
            yield lineno, line[1:]
            lineno += 1


def ordered_folders(root, base, head, changed):
    """Folders whose add-on file gains its `// notchcast-addon-order:` line: the add-ons the branch adds."""
    fork = git('merge-base', base, head, root=root).strip()
    return {folder_of(path) for path in changed if folder_of(path) and path.endswith('.swift')
            and any(ORDER_LINE.match(text) for _, text in added_lines(root, base, head, path))
            and not any(ORDER_LINE.match(line) for line in show(root, fork, path).splitlines())}


def borrowed_changes(root, base, head, owned, changed):
    problems = []
    for path in changed:
        if not path.startswith(BORROWED_DIR):
            continue
        folder = path[len(BORROWED_DIR):].removesuffix('.txt')
        if folder not in owned:
            problems.append(f'{path}: the licence list of {folder}, a folder this branch does not own')
            continue
        for _, text in added_lines(root, base, head, path):
            match = BORROWED_LINE.match(text)
            if not match or match[1] != folder:
                problems.append(f'{path}: "{text.strip()}" is not a `{folder}: <our file> ← <repo>/<file> (<licence>)` line')
    return problems


def feature_gate(root, base, head, changed):
    owned = ordered_folders(root, base, head, changed)
    touched = sorted({f for f in map(folder_of, changed) if f})
    if not owned and len(touched) == 1:
        owned = set(touched)
    folders = sorted(owned)
    problems = borrowed_changes(root, base, head, owned, changed)
    for path in changed:
        if folder_of(path) in owned or path.startswith(BORROWED_DIR):
            continue
        if any(path.startswith(f'Tests/nc-{f}-') and path.endswith('.swift') for f in folders):
            continue
        problems.append(f'{path}: outside the add-on folders {folders or "(none)"}; '
                        'a feature branch touches only its folders, its tests and its licence list')
    return problems, f"feature folders: {', '.join(folders) or '(none)'}"


def show(root, ref, path):
    result = subprocess.run(['git', 'show', f'{ref}:{path}'], cwd=root, capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else ''


def shared_lists(root, base, head, changed):
    """Fails a hand edit of a list made from the add-ons' own files (notchcast/docs/addons.md §1)."""
    problems = []
    fork = git('merge-base', base, head, root=root).strip()
    if REGISTRY in changed and GENERATOR not in changed:
        problems.append(f"{REGISTRY}: generated from each add-on's `// notchcast-addon-order:` line "
                        f'(notchcast/addons.py), never edited; drop the edit: git checkout {base[:12]} -- {REGISTRY}')
    if BORROWED in changed:
        for _, text in added_lines(root, base, head, BORROWED):
            entry = BORROWED_LINE.match(text)
            if CREDIT_LIKE.match(text) or ('←' in text and '<' not in text):
                problems.append(f'{BORROWED}: "{text}" belongs in {BORROWED_DIR}{entry[1] if entry else "<Folder>"}.txt')
    if README_PUBLIC in changed:
        readme = show(root, head, README_PUBLIC).splitlines()
        marks = [n for n, line in enumerate(readme, 1) if line.strip() in TABS]
        # Core text on a tab line (Island) stays core's to edit, and a new tab starts empty; nothing else goes here.
        cored = {m[1] for line in show(root, fork, README_PUBLIC).splitlines() for m in [TAB_LINE.match(line)]
                 if m and m[2].strip()}
        for lineno, text in added_lines(root, base, head, README_PUBLIC):
            tab = TAB_LINE.match(text)
            if len(marks) == 2 and marks[0] < lineno < marks[1] and text.strip() \
                    and not (tab and (tab[1] in cored or not tab[2].strip())):
                problems.append(f'{README_PUBLIC}:{lineno}: a phrase on a tab line; an add-on states it as '
                                '`// notchcast-readme: <Tab>: <phrase>` in its own <Folder>Addon.swift')
    # Only lines the branch adds: a branch cut before the tags still carries main's old lists until it merges.
    for lineno, text in added_lines(root, base, head, CONFIG):
        for name in FORK_HARNESS.findall(text):
            problems.append(f'{CONFIG}:{lineno}: names the fork harness {name}; drop it there and give '
                            f'Tests/{name}.swift a `// notchcast-hosted-only`, `-linux-ok` or `-ci-skip` line '
                            '(notchcast/harness-tags.sh)')
    return problems


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


def run(root, base, head, upstream, mode, branch=''):
    changed = [p for p in git('diff', '--name-only', f'{base}...{head}', root=root).splitlines() if p]
    mode = mode or mode_for_branch(branch, root, base, head, changed)
    if mode == 'core':
        problems, summary = core_gate(root, base, head, upstream, changed)
    elif mode == 'feature':
        problems, summary = feature_gate(root, base, head, changed)
    else:
        problems, summary = [], 'no add-on gate'
    problems += shared_lists(root, base, head, changed)
    problems += guard(root, upstream, head)
    print(f'add-on gate ({mode}): {summary}')
    return problems


CORE_BRANCH = re.compile(r'v2/addons-core(-[0-9]+)?')


def mode_for_branch(branch, root, base, head, changed):
    """Core by name; feature for any other v2/addons-*, or a branch that adds an add-on or touches only one."""
    if CORE_BRANCH.fullmatch(branch):
        return 'core'
    if branch.startswith('v2/addons-'):
        return 'feature'
    touched = {folder_of(path) for path in changed} - {None}
    return 'feature' if len(touched) == 1 or ordered_folders(root, base, head, changed) else 'none'


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--mode', choices=('core', 'feature', 'none'))
    mode.add_argument('--branch')
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--upstream', default=None)
    parser.add_argument('--root', default=str(pathlib.Path(__file__).resolve().parent.parent))
    args = parser.parse_args()
    try:
        upstream = args.upstream or git('merge-base', args.head, 'refs/remotes/upstream/main', root=args.root).strip()
        problems = run(args.root, args.base, args.head, upstream, args.mode, args.branch or '')
    except (Tooling, OSError, ValueError) as error:
        print(f'add-on gate: tooling failure, not a contract breach: {error}', file=sys.stderr)
        return 2
    for problem in problems:
        print(f'::error::{problem}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
