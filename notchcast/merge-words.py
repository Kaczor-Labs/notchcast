#!/usr/bin/env python3
"""git merge driver for files whose lines are lists: merge-words.py %O %A %B (base, ours, theirs).

The same three-way merge git does, on words instead of lines, so two sides that each add a name to one line
merge. Where both sides add different words at one place inside a line, ours go first. Anything else git would
call a conflict (a word both sides changed, a word one side removed beside the other's addition, whole lines both
added at one place, the same name added by both sides at one place among other words) is left to git's own line
merge, so a real conflict looks as it always did.
"""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

# A list separator is its own word, so a name added before a closing quote or after a comma changes no other word.
NAME = r'''[^\s"',;|()]+'''
WORD = re.compile(NAME + r'|\s+|.')


def names(words):
    return {word for word in words if re.fullmatch(NAME, word)}


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
            if names(conflict['ours']) & names(conflict['theirs']):
                return None
            text += added
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
