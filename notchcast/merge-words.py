#!/usr/bin/env python3
"""git merge driver for files whose lines are lists: merge-words.py %O %A %B (base, ours, theirs).

The same three-way merge git does, on words instead of lines, so two sides that each add a name to one line
merge. Where both sides add words at one place inside a line, ours go first. A name both sides added to a quoted
name list (NAME_TESTS="..." or NAME_INPUTS="...") lands once wherever each side put it, as does an entry both
added at one place of a comma list in a table cell; prose, table columns, other quoted values and entries holding
brackets or code keep both sides whole. Anything else git would call a conflict (a word both sides changed, a word
one side removed beside the other's addition, whole lines both added at one place) is left to git's own line
merge, so a real conflict looks as it always did.
"""
from collections import Counter
import difflib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

# A list separator is its own word, so a name added before a closing quote or after a comma changes no other word.
NAME = re.compile(r'''[^\s"',;|()]+''')
WORD = re.compile(NAME.pattern + r'''|\s+|.''')
# A quoted name list is a variable named *_TESTS or *_INPUTS; any other quoted value is merged as text.
LIST_NAME = r'[A-Za-z_]\w*_(?:TESTS|INPUTS)'
OPEN_LIST = re.compile(r'(?:^|\s)' + LIST_NAME + '="[^"]*$')
CELL = re.compile(r'^\s*\|.*\|[^|]*$')
QUOTED_LIST = re.compile(r'^(\s*(?:export\s+)?(' + LIST_NAME + ')=")([^"\n]*)(")', re.M)
NOT_IN_ENTRY = '"\'()`'


def entries(words, between):
    """(name, text) per list entry, each with the separators on its open side, or None for a bare separator."""
    leading, out, seen_name, after_separator = None, [], False, False
    for word in words:
        separator = word in between or (word.isspace() and (after_separator or ' ' in between))
        if leading is None:
            leading = separator
        if not out or (separator and leading and seen_name) or (not separator and not leading and after_separator):
            out.append(['', ''])
            seen_name = False
        out[-1][1] += word
        if not separator:
            out[-1][0] += word
            seen_name = True
        after_separator = separator
    return leading, [(name.strip(), text) for name, text in out]


def is_list(line, ours, theirs):
    """Whether additions at the end of this line so far are list entries rather than prose, cells or values."""
    if any(char in word for word in ours + theirs for char in NOT_IN_ENTRY):
        return False
    if OPEN_LIST.search(line):
        return True
    first = [next((word for word in side if not word.isspace()), '') for side in (ours, theirs)]
    return bool(CELL.match(line)) and '|' not in ours + theirs and first == [',', ',']


def both_added(ours, theirs):
    """Both sides' additions at one place, ours first, with an entry both sides added once."""
    between = ',;|' if any(word in ',;|' for word in ours + theirs) else ' '
    (ours_leading, ours), (theirs_leading, theirs) = entries(ours, between), entries(theirs, between)
    if ours_leading != theirs_leading:
        return [text for _, text in ours + theirs]
    text = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, [n for n, _ in ours], [n for n, _ in theirs],
                                                       autojunk=False).get_opcodes():
        text += [entry for _, entry in ours[i1:i2]]
        if tag != 'equal':
            text += [entry for _, entry in theirs[j1:j2]]
    return text


def merged(base, ours, theirs):
    """The merged text, or None where the line merge must decide."""
    with tempfile.TemporaryDirectory() as scratch:
        sides, sources = [], []
        for name, path in (('ours', ours), ('base', base), ('theirs', theirs)):
            with open(path, encoding='utf-8', newline='') as file:
                source = file.read()
            if name != 'base':
                sources.append(source)
            words = WORD.findall(source)
            sides.append(str(Path(scratch, name)))
            # One JSON string per line: a word that is a line break stays one line, and none can pass for a marker.
            Path(sides[-1]).write_text(''.join(json.dumps(word) + '\n' for word in words), encoding='utf-8')
        # --diff3 names the base words of each conflict, and stops git from splitting a conflict's two sides further.
        result = subprocess.run(['git', 'merge-file', '-p', '--diff3', *sides], capture_output=True, encoding='utf-8')
    if not 0 <= result.returncode <= 127:
        return None
    text, side, conflict = [], None, {}
    for line in result.stdout.splitlines():
        if line.startswith('<<<<<<<'):
            side, conflict = 'ours', {'ours': [], 'base': [], 'theirs': []}
        elif line.startswith('|||||||'):
            side = 'base'
        elif line == '=======':
            side = 'theirs'
        elif line.startswith('>>>>>>>'):
            ours, theirs = conflict['ours'], conflict['theirs']
            if conflict['base'] or any('\n' in word or '\r' in word for word in ours + theirs):
                return None
            listed = is_list(''.join(text).rpartition('\n')[2], ours, theirs)
            text += both_added(ours, theirs) if listed else ours + theirs
            side = None
        elif side:
            conflict[side].append(json.loads(line))
        else:
            text.append(json.loads(line))
    return once(''.join(text), *sources)


def values(text):
    """NAME -> quoted one-line value, for names assigned once."""
    found = {}
    for match in QUOTED_LIST.finditer(text):
        found[match[2]] = None if match[2] in found else match[3]
    return found


def once(text, ours, theirs):
    """Drops a later copy of a name the merge put in a quoted list more often than either side holds it."""
    ours, theirs = values(ours), values(theirs)

    def fix(match):
        name, value = match[2], match[3]
        if ours.get(name) is None or theirs.get(name) is None or any(char in value for char in NOT_IN_ENTRY):
            return match[0]
        allowed = Counter(NAME.findall(ours[name])) | Counter(NAME.findall(theirs[name]))
        parts, seen = re.split('(' + NAME.pattern + ')', value), Counter()
        kept = [parts[0]]
        # A dropped copy always follows a kept one, so it goes with the separator before it.
        for index in range(1, len(parts), 2):
            seen[parts[index]] += 1
            if seen[parts[index]] <= allowed[parts[index]] or not allowed[parts[index]]:
                kept += [parts[index - 1], parts[index]] if index > 1 else [parts[index]]
        return match[1] + ''.join(kept) + (parts[-1] if len(parts) > 1 else '') + match[4]

    return QUOTED_LIST.sub(fix, text)


def main():
    base, ours, theirs = sys.argv[1:4]
    try:
        text = merged(base, ours, theirs)
    except (OSError, ValueError):
        text = None
    if text is None:
        return subprocess.run(['git', 'merge-file', ours, base, theirs]).returncode
    with open(ours, 'w', encoding='utf-8', newline='') as file:
        file.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
