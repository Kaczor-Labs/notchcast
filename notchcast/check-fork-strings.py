#!/usr/bin/env python3
"""Reject fork strings in the upstream table and broken explicit table references."""
import json
from pathlib import Path
import re
import runpy
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / 'Tinycast/Features/Notchcast'
# Unless it names a table, a literal here lands in Localizable; only upstream's own keys may.
LOCALIZING = re.compile(r'(?:String\(\s*localized:|LocalizedStringResource\(|\b(?:Text|TextField|SecureField'
                        r'|Section|Button|Toggle|Picker|LabeledContent|SettingsRow)\(|\.(?:help|navigationTitle'
                        r'|accessibility(?:Label|Hint|Value))\(|(?:title|subtitle|prompt):)\s*$')
CHORD = re.compile(r'[⌃⌥⇧⌘]+[^\s⌃⌥⇧⌘.,;:()]|\bHyper\b')
SYSTEM_KEYS = re.compile(r'^// notchcast-system-keys:(.*)$', re.M)


def undeclared_chords(catalogs):
    """`catalogs` maps a catalog's path to its keys; a chord passes only if its folder declares it."""
    errors = []
    for path, keys in catalogs.items():
        declared = set()
        if path.name != 'Notchcast.xcstrings':
            for source in path.parent.rglob('*.swift'):
                for line in SYSTEM_KEYS.findall(source.read_text()):
                    declared.update(line.split())
        for key in keys:
            for chord in sorted(set(CHORD.findall(key)) - declared):
                errors.append(f'{path.name}: "{key}" names {chord}. A command\'s shortcut is the user\'s and '
                              'its field shows it, so leave it out of the text; a fixed key the feature itself '
                              f'handles is declared in its add-on folder as `// notchcast-system-keys: {chord}`')
    return errors


def check():
    tools = runpy.run_path(str(ROOT / 'notchcast/move-fork-strings.py'))
    local = json.loads((ROOT / tools['LOCAL']).read_bytes())['strings']
    fork_path = ROOT / tools['FORK']
    if not fork_path.exists():
        return ['Notchcast.xcstrings is missing; run move-fork-strings.py']
    fork = json.loads(fork_path.read_bytes())['strings']
    # CI and local-ci check catalogs before their own upstream fetch step.
    if subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '-q', '--verify', 'refs/remotes/upstream/main'],
                      capture_output=True).returncode:
        subprocess.check_call(['git', '-C', str(ROOT), 'fetch', '-q', '--no-tags',
                               "https://github.com/{}.git".format(tools['CONFIG']['UPSTREAM_REPO']), '+refs/heads/main:refs/remotes/upstream/main'])
    # Upstream deletions after our base must not turn inherited strings into fork keys.
    base = subprocess.run(['git', '-C', str(ROOT), 'merge-base', 'HEAD', 'upstream/main'],
                          capture_output=True, text=True)
    upstream_ref = base.stdout.strip() if base.returncode == 0 else 'upstream/main'
    upstream = json.loads(subprocess.check_output([
        'git', '-C', str(ROOT), 'show', upstream_ref + ':' + tools['LOCAL']]))['strings']
    errors = ['fork key in Localizable: ' + key for key in local.keys() - upstream.keys()]
    errors += ['key in both catalogs: ' + key for key in local.keys() & fork.keys()]
    for key, entry in fork.items():
        if entry.get('shouldTranslate') is not False:
            extra = entry.get('localizations', {}).keys() - tools['LOCALES']
            if extra:
                errors.append(f'{key}: non-English localizations {sorted(extra)}')
    tables = {path.stem: json.loads(path.read_bytes())['strings']
              for path in (ROOT / 'Tinycast').rglob('Notchcast?*.xcstrings')}
    errors += undeclared_chords({fork_path: fork} | {
        path: tables[path.stem] for path in (ROOT / 'Tinycast').rglob('Notchcast?*.xcstrings')})
    for path in (ROOT / 'Tinycast').rglob('*.swift'):
        source = path.read_text()
        addon = ADDONS in path.parents
        for start, end, literal in tools['literals'](source):
            table = re.match(r'\s*,\s*table(?:Name)?:\s*"(Notchcast\w*)"', source[end:])
            if table:
                keys = fork if table[1] == 'Notchcast' else tables.get(table[1], {})
                if not any(tools['REFERENCED'](key, literal) for key in keys):
                    errors.append(f'{path.relative_to(ROOT)}: missing key for {literal} in {table[1]}')
            elif addon and LOCALIZING.search(source[:start]) and literal[1:-1] not in upstream:
                errors.append(f'{path.relative_to(ROOT)}: add-on string without a table: {literal}')
        _, pending = tools['rewrite'](source, fork)
        if pending:
            errors.append(f'{path.relative_to(ROOT)}: {pending} fork literals use the default table')
    return errors


if __name__ == '__main__':
    problems = check()
    if not problems:
        subprocess.run(['node', str(ROOT / 'notchcast/check-localizations.js')], check=True)
    print('\n'.join(problems) if problems else 'fork strings: PASS')
    sys.exit(bool(problems))
