#!/usr/bin/env python3
"""Discover and run fork script tests concurrently; --base narrows them to those a diff reaches."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


RUNTIMES = {".py": ["python3"], ".sh": ["bash"], ".mjs": ["node"],
            ".swift": ["swift", "-swift-version", "6"]}
RUNNER = "notchcast/script-tests.py"
# The script tests build their fixtures from these folders; nothing they read lives outside them.
TOOLING = ("notchcast", ".github", "Scripts")


def inputs_of(tests):
    """Each test's inputs: every tooling file it names by file name, and what those name in turn."""
    tracked = subprocess.check_output(["git", "ls-files", "--", *TOOLING], text=True).split()
    by_name = {}
    for path in tracked:
        by_name.setdefault(Path(path).name, set()).add(path)
    named = {}

    def names(path):
        # Docs and vendored sources run nothing, so a file they name is not an input through them.
        if path.endswith(".md") or "/vendor/" in path or not Path(path).is_file():
            return set()
        if path not in named:
            text = Path(path).read_text(errors="replace")
            named[path] = {found for name, paths in by_name.items() if name in text for found in paths}
        return named[path]

    closure = {}
    for test in map(str, tests):
        seen, todo = {test}, [test]
        while todo:
            new = names(todo.pop()) - seen
            seen |= new
            todo.extend(new)
        closure[test] = seen
    return closure


def selected(tests, base):
    """The tests whose inputs the diff from base reaches; every test when that diff cannot be read."""
    try:
        changed = set(subprocess.check_output(["git", "diff", "--name-only", f"{base}...HEAD"],
                                              text=True, stderr=subprocess.DEVNULL).split())
    except (OSError, subprocess.CalledProcessError):
        print(f"script-tests.py: no diff from {base}; running every test", file=sys.stderr, flush=True)
        return tests
    if RUNNER in changed:
        return tests
    closure = inputs_of(tests)
    return [test for test in tests if closure[str(test)] & changed]


def run_test(path):
    """(returncode, combined output, seconds); each test gets its own TMPDIR so no two share a scratch path."""
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix=f"{path.stem}-") as tmp:
        result = subprocess.run([*RUNTIMES[path.suffix], str(path)], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                env={**os.environ, "TMPDIR": tmp + "/"})
    return result.returncode, result.stdout.decode(errors="replace"), time.monotonic() - started


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base", help="run only the tests whose inputs changed since this commit (a PR's base)")
parser.add_argument("--list", action="store_true", help="list selected tests without running them")
parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4, help="tests to run at once")
args = parser.parse_args()
tests = sorted(path for suffix in RUNTIMES for path in Path("notchcast").rglob(f"*-test{suffix}"))
if not tests:
    sys.exit("script-tests.py: no tests found; run it from the repository root")
if args.base:
    tests = selected(tests, args.base)
if args.list:
    print("\n".join(map(str, tests)))
    sys.exit(0)
if not tests:
    print(f"No script tests: the diff from {args.base} reaches none of their inputs", flush=True)
    sys.exit(0)
print(f"Running {len(tests)} script tests, {args.jobs} at a time", flush=True)
started = time.monotonic()
failed = []
with ThreadPoolExecutor(max_workers=args.jobs) as pool:
    futures = {pool.submit(run_test, path): path for path in tests}
    for future in as_completed(futures):
        path = futures[future]
        returncode, output, seconds = future.result()
        verdict = f"FAIL ({returncode})" if returncode else "ok"
        print(f"\n=== {path} {verdict} {seconds:.1f}s ===\n{output}", end="", flush=True)
        if returncode:
            failed.append(str(path))
print(f"\nScript tests: {len(tests) - len(failed)} passed, {len(failed)} failed "
      f"in {time.monotonic() - started:.1f}s", flush=True)
if failed:
    print("\n".join(sorted(failed)), file=sys.stderr)
sys.exit(bool(failed))
