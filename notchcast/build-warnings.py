#!/usr/bin/env python3
"""Compare Xcode build warnings from base and head logs and their source roots."""
import re
import sys
from collections import Counter
from pathlib import Path

WARNING = re.compile(r"(?:^|\s)warning: ")
LOCATION = re.compile(r"(?<=\S):\d+(?::\d+)?:(?= warning: )")


def warnings(log, root):
    paths = (root + "/", str(log.parent / "DerivedData") + "/")
    result = Counter()
    with log.open(errors="replace") as stream:
        for line in stream:
            if WARNING.search(line):
                diagnostic = LOCATION.sub(":", line.strip())
                for path in paths:
                    diagnostic = diagnostic.replace(path, "")
                result[diagnostic] += 1
    return result


def main(base_log, head_log, base_root, head_root):
    new = warnings(Path(head_log), head_root) - warnings(Path(base_log), base_root)
    if new:
        print(f"::error::{sum(new.values())} new Debug build warnings vs base")
        for diagnostic, count in sorted(new.items()):
            print(f"  {count} × {diagnostic}")
        return 1
    print("0 new Debug build warnings vs base")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
