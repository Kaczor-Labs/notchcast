#!/usr/bin/env python3
"""Claude Code PreToolUse hook: refuse `gh pr create` without --draft (wired in .claude/settings.json)."""
import json
import re
import shlex
import sys

SEPARATORS = {';', '&', '&&', '|', '||', '|&', '\n', '(', ')'}
DRAFT = {'--draft', '-d', '--draft=true'}


def commands(line):
    """Each simple command's words, split on shell separators; quoted text stays one word."""
    lexer = shlex.shlex(line, posix=True, punctuation_chars=';&|()\n')
    lexer.whitespace = ' \t\r'
    words = []
    for token in lexer:
        if token in SEPARATORS:
            yield words
            words = []
        elif words or not re.fullmatch(r'\w+=.*', token):
            words.append(token)
    yield words


def refused(line):
    try:
        return any(words[:3] in (['gh', 'pr', 'create'], ['gh', 'pr', 'new']) and not DRAFT & set(words[3:])
                   for words in commands(line))
    except ValueError:
        return False  # shortcut: unparseable quoting is left to bash, which refuses to run it too


if refused(json.load(sys.stdin).get('tool_input', {}).get('command', '')):
    print('Refused: open every PR as a draft with `gh pr create --draft`; '
          'only the lead marks it ready with `gh pr ready`.', file=sys.stderr)
    sys.exit(2)  # Claude Code blocks the tool call only on exit 2
