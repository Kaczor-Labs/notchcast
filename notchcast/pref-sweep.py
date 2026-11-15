#!/usr/bin/env python3
"""Remove the throwaway UserDefaults suites a harness run leaves in ~/Library/Preferences.

Harnesses create `UserDefaults(suiteName: "<name>.<UUID>")` and cfprefsd writes a plist for each,
even after removePersistentDomain. Neither HOME nor CFFIXED_USER_HOME redirects that file, so a run
snapshots the directory when it starts and the last run to finish deletes what is new and named
like a suite the harness sources build: a literal prefix followed by a UUID (`"x.\\(UUID())"`), or an
app domain with "test" in it. Anything else new and UUID-named is left and counted, so a harness
shape the prefixes miss shows up in the log instead of being deleted on a guess.
Overlapping runs share one baseline: a suite one run still uses is never deleted by another.
cfprefsd rewrites a deleted plist from its cache, so each deletion is followed by a `defaults read`,
which makes it reload the missing file, and the sweep repeats until a pass finds nothing new.

    pref-sweep.py begin <pid>   register the run; the first one records the baseline
    pref-sweep.py end <pid>     unregister; the last one out deletes the new test suites

A run killed before `end` leaves its baseline; whichever call next finds no live run sweeps for it.
"""
import fcntl
import os
from pathlib import Path
import re
import subprocess
import sys
import time

PREFS = Path(os.environ.get("NOTCHCAST_PREFS_DIR") or Path.home() / "Library/Preferences")
STATE = Path(os.environ.get("NOTCHCAST_PREF_SWEEP_STATE") or f"/tmp/notchcast-pref-sweep-{os.getuid()}")
MAX_PASSES = 6
SETTLE = float(os.environ.get("NOTCHCAST_PREF_SWEEP_SETTLE", "1"))
SOURCES = Path(os.environ.get("NOTCHCAST_PREF_SWEEP_SOURCES") or Path(__file__).resolve().parent.parent / "Tests")
UUID = re.compile(r"[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")
APP_DOMAINS = ("app.notchcast", "com.tinycast.app")
SUITE_PREFIX = re.compile(r'"([^"\\\n]*)(?:\\\(UUID\(\)|"\s*\+\s*UUID\(\))')
USABLE_PREFIX = re.compile(r"[\w.-]{4,}")


def harness_prefixes() -> set[str]:
    found = set()
    for source in SOURCES.glob("*.swift"):
        found |= {match[1] for match in SUITE_PREFIX.finditer(source.read_text(encoding="utf-8"))}
    return {prefix for prefix in found if USABLE_PREFIX.fullmatch(prefix)}


def is_uuid_named(name: str) -> bool:
    return name.endswith(".plist") and bool(UUID.search(name)) and not name.startswith("com.apple.")


def is_test_suite(name: str, prefixes: set[str]) -> bool:
    if name.startswith(APP_DOMAINS):
        return "test" in name.lower()
    return any(name.startswith(prefix) and UUID.match(name, len(prefix)) for prefix in prefixes)


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def unknown(baseline: set[str], prefixes: set[str]) -> list[str]:
    return sorted(name for name in os.listdir(PREFS)
                  if name not in baseline and is_uuid_named(name) and not is_test_suite(name, prefixes))


def sweep(baseline: set[str], prefixes: set[str]) -> set[str]:
    removed = set()
    for name in os.listdir(PREFS):
        if name not in baseline and is_uuid_named(name) and is_test_suite(name, prefixes):
            try:
                (PREFS / name).unlink()
            except FileNotFoundError:
                continue
            subprocess.run(["/usr/bin/defaults", "read", name.removesuffix(".plist")],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            removed.add(name)
    return removed


def finish(baseline: Path, prefixes: Path) -> None:
    known = set(baseline.read_text(encoding="utf-8").split("\n"))
    allowed = set(prefixes.read_text(encoding="utf-8").split()) if prefixes.exists() else set()
    removed = set()
    for _ in range(MAX_PASSES):
        swept = sweep(known, allowed)
        removed |= swept
        if not swept:
            break
        time.sleep(SETTLE)  # cfprefsd rewrites some of what it was just refused
    left = unknown(known, allowed)
    baseline.unlink()
    prefixes.unlink(missing_ok=True)
    if removed:
        print(f"pref-sweep: removed {len(removed)} leftover test preference suites", file=sys.stderr)
    if left:
        print(f"pref-sweep: left {len(left)} unknown: {' '.join(left[:5])}", file=sys.stderr)


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("begin", "end") or not sys.argv[2].isdigit():
        sys.exit(__doc__)
    command, pid = sys.argv[1], int(sys.argv[2])
    active, baseline, prefixes = STATE / "active", STATE / "baseline", STATE / "prefixes"
    active.mkdir(parents=True, exist_ok=True)
    with open(STATE / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if command == "end":
            (active / str(pid)).unlink(missing_ok=True)
        for entry in active.iterdir():
            if not alive(int(entry.name)):
                entry.unlink()
        if not any(active.iterdir()) and baseline.exists():
            finish(baseline, prefixes)  # also a killed run's sweep, before a begin re-baselines over it
        if command == "begin":
            if not any(active.iterdir()):
                baseline.write_text("\n".join(os.listdir(PREFS)), encoding="utf-8")
                prefixes.unlink(missing_ok=True)
            with open(prefixes, "a", encoding="utf-8") as known_prefixes:
                known_prefixes.writelines(f"{prefix}\n" for prefix in sorted(harness_prefixes()))
            (active / str(pid)).touch()
    return 0

if __name__ == "__main__":
    sys.exit(main())
