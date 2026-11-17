#!/usr/bin/env python3
"""Feed the repo's PreToolUse Bash hook sample commands: only a non-draft `gh pr create` is refused."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
REFUSED = [
    'gh pr create --title "Fix" --body "Closes #1"',
    'gh pr create --fill',
    'gh pr new --fill',
    'gh pr create --draft=false --fill',
    'cd notchcast && gh pr create --fill',
    'git push -u origin HEAD; gh pr create --fill',
    'echo pushed\ngh pr create --fill',
    'GH_TOKEN=x gh pr create --fill',
    "gh pr create --body 'add --draft later' --fill",
    'git push -u origin HEAD  # publish\ngh pr create --fill',
    'gh pr create --title "x" \\\n  --body "y"',
    "cat <<'EOF' > body.md\ngh pr create --draft\nEOF\ngh pr create --body-file body.md",
    'rtk bypass gh pr create --fill',
    'rtk gh pr create --fill',
    'env GH_TOKEN=x gh pr create --fill',
    'command gh pr create --fill',
    'time gh pr create --fill',
    'if true; then gh pr create --fill; fi',
    'for r in a; do gh pr create --fill; done',
    '{ gh pr create --fill; }',
    'git push;\n\ngh pr create --fill',
]
ALLOWED = [
    'gh pr create --draft --fill',
    'gh pr create -d --fill',
    'gh pr create --draft=true --fill',
    'cd notchcast && gh pr create --fill --draft',
    'gh pr new -d --fill',
    'gh pr ready 12',
    'gh pr view 12',
    'gh issue create --title "gh pr create"',
    'echo "gh pr create --fill"',
    "git commit -m 'never gh pr create without a draft'",
    'grep -rn "gh pr create" notchcast',
    'ls',
    'echo "unbalanced',
    'gh pr create --title "x" \\\n  --body "y" \\\n  --draft',
    'gh pr create --title "x" --body "$(cat <<\'EOF\'\nFlip the "Open (beta)" switch.\nEOF\n)" --draft',
    'ls  # gh pr create --fill',
    'rtk bypass gh pr create --draft --fill',
    'env GH_TOKEN=x gh pr create -d --fill',
    'if true; then gh pr create --draft --fill; fi',
]


def hook_command():
    """The command .claude/settings.json runs before every Bash call."""
    settings = json.loads((ROOT / '.claude/settings.json').read_text())
    [entry] = [e for e in settings['hooks']['PreToolUse'] if e['matcher'] == 'Bash']
    [hook] = entry['hooks']
    return hook['command']


def run_hook(command, project_dir=ROOT):
    payload = json.dumps({'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                          'tool_input': {'command': command}})
    return subprocess.run(['bash', '-c', hook_command()], input=payload, capture_output=True, text=True,
                          cwd=ROOT / 'notchcast', env={**os.environ, 'CLAUDE_PROJECT_DIR': str(project_dir)})


class RequireDraftPRTests(unittest.TestCase):
    def test_refuses_non_draft(self):
        for command in REFUSED:
            with self.subTest(command=command):
                result = run_hook(command)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('gh pr create --draft', result.stderr)

    def test_allows_the_rest(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                result = run_hook(command)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_script_never_blocks(self):
        with tempfile.TemporaryDirectory() as empty:
            result = run_hook('gh pr create --fill', project_dir=empty)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
