#!/usr/bin/env python3
"""pr.yml's harness selection: a sure selection is all a PR run's harness job runs, anything else runs the whole suite.

    harness-select.py plan <base> <head>         GITHUB_OUTPUT planned, selected, unsure, only (changed-harnesses.sh)
    harness-select.py misses <failures> <shard>  a failed harness a sure selection left out is a miss

NOTCHCAST_HARNESS_SELECT=on makes plan write `only`, the harnesses to run: the selection when it is sure, else empty,
which runs the whole suite. Any other mode is shadow: `only` stays empty and misses reports what a selection would
have left out. misses reads HARNESS_PLANNED, HARNESS_SELECTED and HARNESS_UNSURE (plan's outputs), HARNESS_TESTS
(the tests step's outcome) and the names ci-tests.sh wrote, one per line. Every line it prints starts with
"harness-select", so `gh run view <run> --log | grep harness-select` shows a run's plan and misses.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ALWAYS = "notchcast-hidden-features-test"
SHOWN = 5


def short(items):
    return ", ".join(items[:SHOWN] + ([f"{len(items) - SHOWN} more"] if len(items) > SHOWN else [])) or "none"


def output_value(value):
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def report(line, annotation="notice"):
    print(f"::{annotation} title=harness-select::{line}" if annotation else line, flush=True)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as out:
            out.write(f"{line}\n\n")


def suite_size():
    names = {path.stem for pattern in ("*-test.swift", "*Tests.swift") for path in Path("Tests").glob(pattern)}
    script = Path("Scripts/run-tests.sh").read_text()
    index = set(re.findall(r"^run (?:(?:slow|-O) )*index (?:-O )*(\S+)", script, re.M))
    hidden = re.search(r'^HIDDEN_TESTS="(.*)"$', Path("notchcast/config.env").read_text(), re.M)
    return len(names - index - set(hidden[1].split() if hidden else ()))


def plan(base, head):
    with tempfile.TemporaryDirectory() as scratch:
        unsure = Path(scratch) / "unsure"
        result = subprocess.run(["bash", "notchcast/changed-harnesses.sh", "--unsure", str(unsure), base, head],
                                capture_output=True, text=True)
        if result.returncode:
            error = (result.stderr.strip().splitlines() or [f"exit {result.returncode}"])[-1]
            selected, reasons = [], [f"selector failed: {error}"]
        else:
            selected, reasons = result.stdout.split(), unsure.read_text().splitlines()
    if not result.returncode and not set(selected) - {ALWAYS}:
        reasons.append("no harness maps to the diff")
    try:
        total = str(suite_size())
    except OSError:
        total = "?"
    mode = os.environ.get("NOTCHCAST_HARNESS_SELECT", "unset")
    only = selected if mode == "on" and not reasons else []
    outputs = {"planned": "true", "selected": " ".join(selected), "unsure": short(reasons) if reasons else "",
               "only": " ".join(only)}
    if path := os.environ.get("GITHUB_OUTPUT"):
        with open(path, "a") as out:
            out.writelines(f"{key}={output_value(value)}\n" for key, value in outputs.items())
    report(f"harness-select plan: mode={mode} selected={len(selected)}/{total} unsure={outputs['unsure'] or 'no'}"
           f" runs={'the selection' if only else 'the whole suite'}")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as out:
            out.write("<details><summary>Selected harnesses</summary>\n\n" + "\n".join(selected) + "\n\n</details>\n\n"
                      + "".join(f"- {reason}\n" for reason in reasons))


def misses(failures, shard):
    failed = sorted(set(Path(failures).read_text().split())) if Path(failures).is_file() else []
    selected = set(os.environ.get("HARNESS_SELECTED", "").split())
    unsure = os.environ.get("HARNESS_UNSURE", "")
    outside = [name for name in failed if name not in selected]
    line = f"harness-select shard {shard}: failed={short(failed)} outside={short(outside)}"
    if os.environ.get("HARNESS_PLANNED") != "true":
        report(f"{line} misses=unjudged (no selection was planned)", annotation=None)
        return
    if unsure:
        report(f"{line} unsure={unsure} misses=none (unsure runs the whole suite)", annotation=None)
        return
    if not failed and (outcome := os.environ.get("HARNESS_TESTS") or "unknown") != "success":
        report(f"{line} unsure=no misses=unjudged (tests {outcome}, no failed harness named)", annotation=None)
        return
    for name in outside:
        report(f"harness-select miss: {name} failed in shard {shard}, outside the selection", annotation="warning")
    report(f"{line} unsure=no misses={short(outside)}", annotation=None)


if __name__ == "__main__":
    if sys.argv[1:2] == ["plan"] and len(sys.argv) == 4:
        plan(*sys.argv[2:])
    elif sys.argv[1:2] == ["misses"] and len(sys.argv) == 4:
        misses(*sys.argv[2:])
    else:
        sys.exit(__doc__)
