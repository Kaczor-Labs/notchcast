#!/usr/bin/env python3
import runpy
from pathlib import Path

module = runpy.run_path(str(Path(__file__).with_name("route.py")))
route, decide, hosted_busy = module["route"], module["decide"], module["hosted_busy"]
NOW = 1_000_000
OWNER = {"ACTOR": "owner", "OWNER": "owner", "REPO": "owner/repo"}


def pool(count, idle, busy, queued=(0, 0), **env):
    return route({**OWNER, "COUNT": str(count), "IDLE": "\n".join(idle), "EVENT": "push", **env}, NOW, busy, *queued)


fresh = [f"2 {NOW - 30}", f"1 {NOW - 150}"]
assert pool(4, fresh, 0) == ["xcode-27"] * 4
assert pool(4, fresh, 3) == ["xcode-27"] * 2 + ["notchcast-mac"] * 2
assert pool(7, fresh, 0) == ["xcode-27"] * 5 + ["notchcast-mac"] * 2
assert pool(9, fresh, 0) == ["xcode-27"] * 5 + ["notchcast-mac"] * 3 + ["xcode-27"]
assert pool(3, fresh, 9) == ["notchcast-mac"] * 3
assert pool(2, fresh, 5, EVENT="workflow_dispatch") == ["notchcast-mac"] * 2
assert pool(0, fresh, 0) == []
assert pool(2, fresh, None) == ["xcode-27"] * 2
print("PASS: hosted while a slot is free, then idle Macs; no hosted count is all hosted")

stale = [f"2 {NOW - 151}", "", "soon", f"-1 {NOW}", f"many {NOW}", f"1.5 {NOW}", f"1 {NOW} auto", f"1 {NOW + 61}"]
assert pool(2, stale, 5) == ["xcode-27"] * 2
assert route({**OWNER, "COUNT": "1", "EVENT": "push"}, NOW, 5) == ["xcode-27"]
assert pool("many", fresh, 5) == []
asleep = [f"1 {NOW - 1000}", f"0 {NOW - 1000}"]
assert pool(9, asleep, 0) == ["xcode-27"] * 9
assert pool(4, asleep, 5) == ["xcode-27"] * 4
assert pool(3, [f"-1 {NOW}"], 5) == ["xcode-27"] * 3
print("PASS: a stale, malformed, refusing or missing idle count is no Mac")

same = {"EVENT": "pull_request", "HEAD_REPO": "owner/repo"}
assert pool(1, fresh, 5, **same, ACTION="ready_for_review") == ["notchcast-mac"]
assert pool(1, fresh, 5, **same, ACTION="synchronize") == ["xcode-27"]
assert pool(1, fresh, 5, **same, ACTION="opened", ELIGIBLE="false") == ["xcode-27"]
assert pool(1, fresh, 5, EVENT="pull_request", HEAD_REPO="fork/repo", ACTION="opened") == ["xcode-27"]
assert pool(1, fresh, 5, EVENT="pull_request_target", HEAD_REPO="owner/repo") == ["xcode-27"]
assert pool(1, fresh, 5, ACTOR="someone") == ["xcode-27"]
assert route({"COUNT": "1", "IDLE": "\n".join(fresh), "EVENT": "push"}, NOW, 5) == ["xcode-27"]
print("PASS: only the owner's own refs reach a Mac")

three_busy = [f"0 {NOW}"] * 3
assert pool(4, three_busy, 5, (2, 39)) == ["xcode-27"] * 4
assert pool(4, three_busy, 5, (20, 3)) == ["notchcast-mac"] * 4
assert pool(4, three_busy, 5, (5, 3)) == ["xcode-27", "notchcast-mac", "xcode-27", "notchcast-mac"]
assert pool(1, three_busy, 5, (5, 3)) == ["xcode-27"]
assert pool(2, [f"1 {NOW}"], 5, (0, 9)) == ["notchcast-mac", "xcode-27"]
assert pool(3, [f"1 {NOW}"], 4) == ["xcode-27", "notchcast-mac", "xcode-27"]
assert pool(3, [f"-1 {NOW}", f"0 {NOW}"], 5, (2, 0)) == ["notchcast-mac", "xcode-27", "xcode-27"]
print("PASS: with both full, each job takes the queue with the shorter expected wait; a tie goes hosted")


def api(queued, active, jobs):
    def fetch(path):
        if "/actions/runs?" in path:
            status = path.split("status=")[1].split("&")[0]
            return {"workflow_runs": [{"id": run} for run in (queued if status == "queued" else active)]}
        return {"jobs": jobs[int(path.split("/runs/")[1].split("/")[0])]}

    return fetch


def failing(path):
    raise OSError("api down")


jobs = {
    1: [
        {"status": "queued", "labels": ["xcode-27"]},
        {"status": "in_progress", "labels": ["macos-latest"]},
        {"status": "completed", "labels": ["xcode-27"]},
        {"status": "queued", "labels": ["notchcast-mac"]},
        {"status": "queued", "labels": ["ubuntu-latest"]},
    ],
    2: [{"status": "in_progress", "labels": ["macos-14"]}],
    3: [{"status": "queued", "labels": ["self-hosted", "notchcast-mac"]}] * 39
    + [{"status": "in_progress", "labels": ["xcode-27"]}] * 3
    + [{"status": "queued", "labels": ["xcode-27"]}] * 2,
}
assert hosted_busy("owner/repo", api([1], [2], jobs)) == (3, 1, 1)
assert hosted_busy("owner/repo", api([1], [1, 2], jobs)) == (3, 1, 1)
assert hosted_busy("owner/repo", api([], [], jobs)) == (0, 0, 0)
assert hosted_busy("owner/repo", api([], [3], jobs)) == (5, 2, 39)
print("PASS: hosted count is queued or running macOS jobs on the hosted image, with both queue depths, a run listed twice counted once")

measured = {**OWNER, "COUNT": "4", "IDLE": "\n".join(three_busy), "EVENT": "push"}
assert decide(measured, NOW, api([], [3], jobs)) == ["xcode-27"] * 4
assert decide(measured, NOW, failing) == ["xcode-27"] * 4
print("PASS: the measured backlog (39 queued on 3 busy Macs, hosted full with 2 queued) goes hosted")

spill = {**OWNER, "COUNT": "7", "IDLE": "\n".join(fresh), "EVENT": "push"}
assert decide(spill, NOW, api([], [], jobs)) == ["xcode-27"] * 5 + ["notchcast-mac"] * 2
assert decide(spill, NOW, failing) == ["xcode-27"] * 7
assert decide({**OWNER, "COUNT": "2", "IDLE": "", "EVENT": "push"}, NOW, api([], [], jobs)) == ["xcode-27"] * 2
assert decide({**OWNER, "COUNT": "2", "IDLE": "", "EVENT": "push", "ACTOR": "someone"}, NOW, failing) == ["xcode-27"] * 2
assert decide({**OWNER, "COUNT": "0", "IDLE": "", "EVENT": "push"}, NOW, failing) == []
print("PASS: the Macs take the overflow past the hosted slots; an API failure keeps every job hosted")
