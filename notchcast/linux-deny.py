#!/usr/bin/env python3
"""Add a Linux landing's cause to LINUX_DENY_INPUTS (config.env), for land.sh --guard's revert.

    linux-deny.py <base> <head> <harness>...

The cause is every path the diff changed that one of the named harnesses, red on macOS after passing on Linux, takes as
an input. Prints the paths it added.
"""
import fnmatch
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness_inputs import harnesses


def main(base, head, *names):
    changed = set(subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", "-z", base, head], text=True).split("\0")) - {""}
    cause = set()
    for path, inputs in harnesses():
        if path.stem in names:
            cause |= {file for file in changed if file == str(path)
                      or any(fnmatch.fnmatchcase(file, pattern) for pattern in inputs.patterns + inputs.reads)}
    config = Path("notchcast/config.env")
    text = config.read_text()
    listed = re.search(r'^LINUX_DENY_INPUTS="(.*)"$', text, re.M)
    if not listed:
        sys.exit("notchcast/config.env has no LINUX_DENY_INPUTS line")
    added = sorted(cause - set(listed[1].split()))
    if added:
        config.write_text(text[:listed.start(1)] + " ".join([*listed[1].split(), *added]) + text[listed.end(1):])
    print("\n".join(added))


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
