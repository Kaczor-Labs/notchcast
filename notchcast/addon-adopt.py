#!/usr/bin/env python3
"""One-shot move of an open PR branch onto per-add-on declarations (#1109); delete it once no PR predates them.

Run in the PR's own checkout, on its branch, with a clean tree:
  git fetch origin && git show origin/main:notchcast/addon-adopt.py | python3 -
It rewrites what the branch added to a shared list since it left main into the add-on's own files, puts each
shared list back as the branch found it, commits, then merges origin/main, whose generator builds the registry
back with the add-on in it; nothing is pushed. Then check it and push. A merge conflict left is never a list.
  NotchcastRegistry.swift line   -> `// notchcast-addon-order: <n>` atop the add-on's file (main's order if main has
                                    it, else one between its neighbours in the branch's registry)
  licenses/borrowed.md lines     -> notchcast/licenses/borrowed/<Folder>.txt
  config.env harness-list names  -> `// notchcast-hosted-only` / `-linux-ok` / `-ci-skip` atop the fork harness
  README.public.md tab phrase    -> `// notchcast-readme: <Tab>: <phrase>` in the add-on's file
  docs/addons.md table-row edits -> dropped (printed; the table no longer lists built add-ons)
"""
import difflib
import os
import pathlib
import re
import subprocess
import sys

ROOT_DIR = 'Tinycast/Features/Notchcast/'
REGISTRY = ROOT_DIR + 'NotchcastRegistry.swift'
BORROWED = 'notchcast/licenses/borrowed.md'
CONFIG = 'notchcast/config.env'
README = 'notchcast/README.public.md'
ADDONS_DOC = 'notchcast/docs/addons.md'
ADDON_DECL = re.compile(r'\b(?:struct|enum|class)\s+(\w+)\b[^{]*\bNotchcastAddon\b')
ORDER = re.compile(r'^// notchcast-addon-order: *(\d+)$', re.M)
REGISTRY_LINE = re.compile(r'^\s*(\w+)\.self,\s*$')
BORROWED_LINE = re.compile(r'^(\w+): \S+ ← \S+/\S+ \([^)]+\)$')
TAB_LINE = re.compile(r'^  - \*\*(.+?)\*\*:(.*)$')
TAGS = {'HOSTED_ONLY_TESTS': 'hosted-only', 'LINUX_OK_TESTS': 'linux-ok', 'CI_SKIP_TESTS': 'ci-skip'}
FORK_HARNESS = re.compile(r'^(?:nc|notchcast)-')
# swiftlint fails a line over 200 characters, comments included.
MAX_LINE = 200


def git(*args, check=True):
    result = subprocess.run(['git', *args], capture_output=True, text=True)
    if check and result.returncode:
        sys.exit(f'git {" ".join(args)}: {result.stderr.strip()}')
    return result.stdout


def show(ref, path):
    result = subprocess.run(['git', 'show', f'{ref}:{path}'], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def added(base, path):
    return [line[1:] for line in git('diff', '-U0', base, 'HEAD', '--', path).splitlines()
            if line.startswith('+') and not line.startswith('+++')]


def prepend(path, lines):
    file = pathlib.Path(path)
    text = file.read_text()
    new = [line for line in lines if line not in text.splitlines()]
    if new:
        file.write_text(''.join(f'{line}\n' for line in new) + text)


def main_orders():
    orders = {}
    for path in git('ls-tree', '-r', '--name-only', 'origin/main', '--', ROOT_DIR).splitlines():
        if path.endswith('.swift'):
            text = show('origin/main', path) or ''
            order, types = ORDER.search(text), ADDON_DECL.findall(text)
            if order and len(types) == 1:
                orders[types[0]] = int(order[1])
    return orders


def addon_files():
    files = {}
    for path in sorted(pathlib.Path(ROOT_DIR).rglob('*.swift')):
        for addon in ADDON_DECL.findall(path.read_text()):
            files[addon] = str(path)
    return files


def split_phrase(prefix, phrase):
    """Lines `<prefix><part>` under MAX_LINE, cut at ', ', which the README joins them with again."""
    lines, part = [], ''
    for piece in phrase.split(', '):
        candidate = f'{part}, {piece}' if part else piece
        if part and len(prefix + candidate) > MAX_LINE:
            lines.append(prefix + part)
            candidate = piece
        part = candidate
    return lines + [prefix + part]


def place(order_of, branch_list, addon, on_main):
    """An order between the add-on's neighbours in the branch's registry, so it keeps the place its line had."""
    at = branch_list.index(addon)
    before = next((order_of[a] for a in reversed(branch_list[:at]) if a in order_of), 0)
    after = next((on_main[a] for a in branch_list[at + 1:] if a in on_main and on_main[a] > before), None)
    if after is None:
        return max([*order_of.values(), *on_main.values(), 0]) + 10
    return before + (after - before) // 2 if after - before >= 2 else None


def main():
    os.chdir(git('rev-parse', '--show-toplevel').strip())
    if git('status', '--porcelain').strip():
        sys.exit('commit or drop your changes first: the tree must be clean')
    if not show('origin/main', 'notchcast/addons.py'):
        sys.exit('origin/main has no notchcast/addons.py yet: run `git fetch origin` once #1109 has landed')
    base = git('merge-base', 'HEAD', 'origin/main').strip()
    notes, moved = [], []
    files = addon_files()
    on_main = main_orders()
    new_types = [m[1] for m in map(REGISTRY_LINE.match, added(base, REGISTRY)) if m]
    branch_list = [m[1] for m in map(REGISTRY_LINE.match, pathlib.Path(REGISTRY).read_text().splitlines()) if m] \
        if new_types else []
    order_of, readme_of = dict(on_main), {}
    for addon in [a for a in branch_list if a in new_types]:
        if addon not in files:
            notes.append(f'{REGISTRY}: {addon} is declared in no add-on file; its line is dropped')
            continue
        order = on_main.get(addon) or place(order_of, branch_list, addon, on_main)
        if order is None:
            order = max(order_of.values()) + 10
            notes.append(f'{addon}: no free order between its neighbours; it goes last ({order}), so move it by hand')
        order_of[addon] = order
        readme_of[addon] = files[addon]
        prepend(files[addon], [f'// notchcast-addon-order: {order}'])
        moved.append(f'{addon}: order {order}')
    if new_types:
        git('checkout', base, '--', REGISTRY)

    lines = [line for line in added(base, BORROWED) if BORROWED_LINE.match(line)]
    notes += [f'{BORROWED}: could not read "{line}"; add it by hand to notchcast/licenses/borrowed/<Folder>.txt'
              for line in added(base, BORROWED) if line.strip() and not BORROWED_LINE.match(line)]
    for line in lines:
        target = pathlib.Path(f'notchcast/licenses/borrowed/{BORROWED_LINE.match(line)[1]}.txt')
        target.parent.mkdir(parents=True, exist_ok=True)
        text = target.read_text() if target.exists() else ''
        if line not in text.splitlines():
            target.write_text(text + line + '\n')
    if added(base, BORROWED):
        git('checkout', base, '--', BORROWED)
        moved.append(f'{len(lines)} licence lines -> notchcast/licenses/borrowed/')

    config, before = pathlib.Path(CONFIG), show(base, CONFIG) or ''
    if config.exists() and config.read_text() != before:
        text = config.read_text()
        for key, tag in TAGS.items():
            now = re.search(rf'^{key}="(.*)"$', text, re.M)
            then = re.search(rf'^{key}="(.*)"$', before, re.M)
            if not now or not then:
                continue
            old = then[1].split()
            for name in [n for n in now[1].split() if n not in old and FORK_HARNESS.match(n)]:
                harness = pathlib.Path(f'Tests/{name}.swift')
                if harness.exists():
                    prepend(harness, [f'// notchcast-{tag}'])
                    moved.append(f'{name}: {key} -> // notchcast-{tag}')
                else:
                    notes.append(f'{CONFIG}: {key} names {name}, which is no harness here; dropped')
            kept = old + [n for n in now[1].split() if n not in old and not FORK_HARNESS.match(n)]
            text = text[:now.start(1)] + ' '.join(kept) + text[now.end(1):]
        config.write_text(text)

    readme, before = pathlib.Path(README), show(base, README)
    if before is not None and readme.exists() and readme.read_text() != before:
        old_tabs = {m[1]: line for line in before.splitlines() for m in [TAB_LINE.match(line)] if m}
        out = []
        for line in readme.read_text().splitlines(keepends=True):
            match = TAB_LINE.match(line.rstrip('\n'))
            if not match or match[1] not in old_tabs or line.rstrip('\n') == old_tabs[match[1]]:
                out.append(line)
                continue
            was = old_tabs[match[1]].rstrip('.')
            phrase = line.rstrip('\n').rstrip('.')[len(was):].lstrip(';,. ') if line.startswith(was) else ''
            owner = next((a for a in readme_of if a.removesuffix('Addon').lower() in phrase.lower()),
                         next(iter(readme_of), None))
            if not phrase or owner is None:
                notes.append(f'{README}: could not place your edit to the **{match[1]}** line; '
                             f'add a `// notchcast-readme:` line by hand: {line.strip()}')
                out.append(old_tabs[match[1]] + '\n')
                continue
            file = pathlib.Path(readme_of[owner])
            text = file.read_text().split('\n')
            at = next(i for i, l in enumerate(text) if ORDER.match(l)) + 1
            text[at:at] = split_phrase(f'// notchcast-readme: {match[1]}: ', phrase)
            file.write_text('\n'.join(text))
            moved.append(f'{owner}: README phrase on **{match[1]}**')
            out.append(old_tabs[match[1]] + '\n')
        readme.write_text(''.join(out))

    doc, before = pathlib.Path(ADDONS_DOC), show(base, ADDONS_DOC)
    if before is not None and doc.exists() and doc.read_text() != before:
        old_lines, new_lines = before.splitlines(keepends=True), doc.read_text().splitlines(keepends=True)
        out = []
        for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False).get_opcodes():
            rows = all(line.startswith('| ') for line in old_lines[i1:i2] + new_lines[j1:j2])
            if tag == 'replace' and rows and i2 - i1 == j2 - j1:
                out += old_lines[i1:i2]
                notes += [f'{ADDONS_DOC}: dropped your table edit (re-apply a Tab cell by hand): {line.strip()}'
                          for line in new_lines[j1:j2]]
            else:
                out += new_lines[j1:j2]
        doc.write_text(''.join(out))

    for line in moved + notes:
        print(line)
    if not git('status', '--porcelain').strip():
        print('nothing to adopt: the branch adds no line to a shared add-on list')
        return 0
    git('add', '-A')
    git('commit', '-q', '-m', 'Notchcast: declare the add-on in its own files (#1109)\n\n'
        'Moved by notchcast/addon-adopt.py off the shared lists.')
    print(f'committed {git("rev-parse", "--short", "HEAD").strip()}')
    # Until main's generator is on the branch, the reset registry would leave the add-on out of the build.
    if subprocess.run(['git', 'merge', '--no-edit', '-q', 'origin/main']).returncode:
        conflicts = git('diff', '--name-only', '--diff-filter=U').split()
        print(f'merging origin/main left conflicts to resolve: {" ".join(conflicts)}; '
              'resolve them, commit, then push')
        return 1
    print('merged origin/main; check it, then push')
    return 0


if __name__ == '__main__':
    sys.exit(main())
