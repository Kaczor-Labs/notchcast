#!/usr/bin/env python3
"""Harness wall times recorded on main, and the CI queue filter that packs shards by them."""
import os
import re
import statistics
import sys

ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.+"
OK = re.compile(r"\] ok\s+(\S+)\s+([\d.]+)s\s+\(compile ([\d.]+)s\)")


def parse(text):
    times = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2:
            try:
                times[parts[0]] = float(parts[1])
            except ValueError:
                pass
    return times


def record(log):
    times = {}
    for line in re.sub(r"\x1b\[[0-9;]*m", "", log).splitlines():
        match = OK.search(line)
        if match:
            times[match[1]] = round(float(match[2]) + float(match[3]), 1)
    return "".join(f"{name} {seconds}\n" for name, seconds in sorted(times.items()))


def name_hash(name):
    value = 0
    for char in name:
        value = (value * 31 + ALPHABET.find(char) + 1) % 1000003
    return value


def pack(names, times, count):
    """Shard of each name: longest first onto the lightest shard; an unknown name weighs the known median."""
    known = [times[name] for name in names if name in times]
    median = statistics.median(known) if known else 0.0
    weight = {name: times.get(name, median) for name in names}
    loads = [0.0] * count
    shard = {}
    for name in sorted(names, key=lambda name: (-weight[name], name)):
        index = loads.index(min(loads))
        shard[name] = index
        loads[index] += weight[name]
    return shard, weight, loads


def narrow(lines, only, skip, shard, times):
    """Kept queue lines and the stderr report, as test-harnesses.sh hands them back to the runner."""
    index, count = (int(part) for part in (shard or "0 1").split())
    only, skip = set(only.split()), set(skip.split())
    rows = [line.split(" ", 2) for line in lines if line.strip()]
    rows = [row for row in rows if not only or row[1] in only]
    names = [row[1] for row in rows]
    report = []
    if times:
        place, weight, loads = pack(names, times, count)
        unknown = sum(name not in times for name in names)
        report.append(f"split: by recorded time, {len(names) - unknown} known, {unknown} at the median")
        if count > 1:
            report.append(f"split: shard loads {', '.join(f'{load:.0f}s' for load in loads)}")
        rows = sorted((row for row in rows if place[row[1]] == index), key=lambda row: -weight[row[1]])
        # The runner dispatches by this rank, so the longest harness of the shard starts first.
        rows = [[str(rank), *row[1:]] for rank, row in enumerate(rows)]
    else:
        if count > 1:
            report.append("split: by name hash, no recorded times")
        rows = [row for row in rows if name_hash(row[1]) % count == index]
    total = sum(name not in skip for name in names)
    kept = []
    for row in rows:
        if row[1] in skip:
            report.append(f"skipped on the runner: {row[1]}")
        else:
            kept.append(" ".join(row) + "\n")
    if count > 1:
        report.append(f"shard {index} of {count}: {len(kept)} of {total} harnesses")
    return kept, report


def main(argv, env):
    if argv[:1] == ["record"] and len(argv) == 3:
        text = record(open(argv[1], errors="replace").read())
        with open(argv[2], "w") as out:
            out.write(text)
        return 0
    if argv[:1] == ["filter"] and len(argv) == 2:
        with open(argv[1]) as queue:
            kept, report = narrow(queue.read().splitlines(), env.get("NOTCHCAST_ONLY_TESTS", ""),
                                  env.get("CI_SKIP_TESTS", ""), env.get("NOTCHCAST_SHARD", ""),
                                  parse(env.get("NOTCHCAST_TIMES", "")))
        with open(argv[1] + ".kept", "w") as out:
            out.writelines(kept)
        for line in report:
            print(line, file=sys.stderr)
        return 0
    print("usage: harness-times.py record LOG OUT | filter QUEUE", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:], os.environ))
