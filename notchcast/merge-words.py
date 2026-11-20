#!/usr/bin/env python3
"""git merge driver for files whose lines are lists: merge-words.py %O %A %B (base, ours, theirs).

The same three-way merge git does, on words instead of lines, so two sides that each add a name to one line
merge. Where both sides add entries at one place inside a line, ours go first and an entry both added lands once.
Anything else git would call a conflict (a word both sides changed, a word one side removed beside the other's
addition, whole lines both added at one place) is left to git's own line merge, so a real conflict looks as it always did.
"""
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


def entries(words, between):
    """(name, text) per list entry, each with the separators on its open side, or None for a bare separator."""
    leading, out, seen_name, after_separator = None, [], False, False
    for word in words:
        separator = word in between or word in '"\'()' or (word.isspace() and (after_separator or ' ' in between))
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
        sides = []
        for name, path in (('ours', ours), ('base', base), ('theirs', theirs)):
            with open(path, encoding='utf-8', newline='') as file:
                words = WORD.findall(file.read())
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
            added = conflict['ours'] + conflict['theirs']
            if conflict['base'] or any('\n' in word or '\r' in word for word in added):
                return None
            text += both_added(conflict['ours'], conflict['theirs'])
            side = None
        elif side:
            conflict[side].append(json.loads(line))
        else:
            text.append(json.loads(line))
    return ''.join(text)


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
