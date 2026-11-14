#!/usr/bin/env python3
"""Remove the throwaway UserDefaults suites a harness run leaves in ~/Library/Preferences.

Harnesses create `UserDefaults(suiteName: "<name>.<UUID>")` and cfprefsd writes a plist for each,
even after removePersistentDomain. Neither HOME nor CFFIXED_USER_HOME redirects that file, so a run
snapshots the directory when it starts and the last run to finish deletes what is new and UUID-named.
Overlapping runs share one baseline: a suite one run still uses is never deleted by another.
cfprefsd rewrites a deleted plist from its cache, so each deletion is followed by a `defaults read`,
which makes it reload the missing file, and the sweep repeats until a pass finds nothing new.

    pref-sweep.py begin <pid>   register the run; the first one records the baseline
    pref-sweep.py end <pid>     unregister; the last one out deletes the new test suites
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
UUID = re.compile(r"[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")
APP_DOMAINS = ("app.notchcast", "com.tinycast.app")


def is_test_suite(name: str) -> bool:
    if not (name.endswith(".plist") and UUID.search(name)):
        return False
    return not name.startswith(APP_DOMAINS) or "test" in name.lower()


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def sweep(baseline: set[str]) -> set[str]:
    removed = set()
    for name in os.listdir(PREFS):
        if name not in baseline and is_test_suite(name):
            try:
                (PREFS / name).unlink()
            except FileNotFoundError:
                continue
            subprocess.run(["/usr/bin/defaults", "read", name.removesuffix(".plist")],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            removed.add(name)
    return removed


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("begin", "end") or not sys.argv[2].isdigit():
        sys.exit(__doc__)
    command, pid = sys.argv[1], int(sys.argv[2])
    active, baseline = STATE / "active", STATE / "baseline"
    active.mkdir(parents=True, exist_ok=True)
    with open(STATE / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if command == "end":
            (active / str(pid)).unlink(missing_ok=True)
        for entry in active.iterdir():
            if not alive(int(entry.name)):
                entry.unlink()
        if command == "begin":
            if not any(active.iterdir()):
                baseline.write_text("\n".join(os.listdir(PREFS)), encoding="utf-8")
            (active / str(pid)).touch()
        elif not any(active.iterdir()) and baseline.exists():
            known = set(baseline.read_text(encoding="utf-8").split("\n"))
            removed = set()
            for _ in range(MAX_PASSES):
                swept = sweep(known)
                removed |= swept
                if not swept:
                    break
                time.sleep(SETTLE)  # cfprefsd rewrites some of what it was just refused
            baseline.unlink()
            if removed:
                print(f"pref-sweep: removed {len(removed)} leftover test preference suites", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
