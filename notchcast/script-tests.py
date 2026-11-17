#!/usr/bin/env python3
"""Discover and run fork script tests concurrently."""
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
LAND_TEST = Path("notchcast/land-test.sh")
LAND_INPUTS = [*Path(__file__).with_name("land-tooling.txt").read_text().split(), str(LAND_TEST)]


def land_inputs_changed():
    # A diff that cannot be read (no base fetched) runs the test rather than skipping it.
    base = os.environ.get("BASE_SHA") or "origin/main"
    try:
        return bool(subprocess.check_output(["git", "diff", "--name-only", f"{base}...HEAD", "--", *LAND_INPUTS],
                                            text=True, stderr=subprocess.DEVNULL).strip())
    except (OSError, subprocess.CalledProcessError):
        return True


def run_test(path):
    """(returncode, combined output, seconds); each test gets its own TMPDIR so no two share a scratch path."""
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix=f"{path.stem}-") as tmp:
        result = subprocess.run([*RUNTIMES[path.suffix], str(path)], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                env={**os.environ, "TMPDIR": tmp + "/"})
    return result.returncode, result.stdout.decode(errors="replace"), time.monotonic() - started


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--all", action="store_true", help="run land-test.sh even when its inputs did not change")
parser.add_argument("--list", action="store_true", help="list selected tests without running them")
parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4, help="tests to run at once")
args = parser.parse_args()
tests = sorted(path for suffix in RUNTIMES for path in Path("notchcast").rglob(f"*-test{suffix}"))
if not tests:
    sys.exit("script-tests.py: no tests found; run it from the repository root")
if not args.all and LAND_TEST in tests and not land_inputs_changed():
    tests.remove(LAND_TEST)
    print(f"Skipping {LAND_TEST}: the diff does not touch {', '.join(LAND_INPUTS)}", file=sys.stderr, flush=True)
if args.list:
    print("\n".join(map(str, tests)))
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
