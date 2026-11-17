#!/usr/bin/env python3
"""Print the runs-on label of each of COUNT macOS jobs: the hosted image, then the maintainer Mac pool."""
import json
import os
import sys
import time
import urllib.request

HOSTED = "xcode-27"
MAC = "notchcast-mac"
HOSTED_SLOTS = 5
# gate.sh rewrites its variable every 60 s, so one that missed two turns is a Mac that is asleep or offline.
FRESH = 150
ACTIVE = ("queued", "in_progress")


def takes_macs(env):
    if not env.get("OWNER") or env.get("ACTOR") != env.get("OWNER") or env.get("ELIGIBLE", "true") != "true":
        return False
    if env.get("EVENT") in ("push", "workflow_dispatch"):
        return True
    return env.get("EVENT") == "pull_request" and env.get("HEAD_REPO") == env.get("REPO")


def count_of(env):
    try:
        return int(env.get("COUNT") or 0)
    except ValueError:
        return 0


def fresh(lines, now):
    """Idle counts of Macs that reported in time and take jobs; gate.sh publishes -1 while refusing."""
    counts = []
    for line in lines.splitlines():
        try:
            count, stamp = (int(part) for part in line.split())
        except ValueError:
            continue
        if count >= 0 and -60 <= now - stamp <= FRESH:
            counts.append(count)
    return counts


def hosted(label):
    return label == HOSTED or label.startswith("macos-")


def hosted_busy(repo, fetch):
    """Queued or running hosted macOS jobs, then queued hosted jobs and queued Mac pool jobs."""
    busy = hosted_queued = mac_queued = 0
    seen = set()
    for status in ACTIVE:
        for run in fetch(f"/repos/{repo}/actions/runs?status={status}&per_page=100")["workflow_runs"]:
            if run["id"] in seen:
                continue
            seen.add(run["id"])
            for job in fetch(f"/repos/{repo}/actions/runs/{run['id']}/jobs?filter=latest&per_page=100")["jobs"]:
                if job["status"] not in ACTIVE:
                    continue
                queued = job["status"] == "queued"
                if any(hosted(label) for label in job["labels"]):
                    busy += 1
                    hosted_queued += queued
                elif MAC in job["labels"]:
                    mac_queued += queued
    return busy, hosted_queued, mac_queued


def route(env, now, busy=None, hosted_queued=0, mac_queued=0):
    """Labels for COUNT jobs. busy is the hosted count, or None when the API could not say."""
    count = count_of(env)
    if not takes_macs(env):
        return [HOSTED] * count
    online = fresh(env.get("IDLE") or "", now)
    if busy is None or not online:
        return [HOSTED] * count
    # A free hosted slot first, then an idle Mac, then the queue with the shorter expected wait.
    free = max(HOSTED_SLOTS - busy, 0)
    pool = sum(online)
    labels = []
    for _ in range(count):
        if free > 0:
            labels.append(HOSTED)
            free -= 1
        elif pool > 0:
            labels.append(MAC)
            pool -= 1
        elif mac_queued * HOSTED_SLOTS < hosted_queued * len(online):
            labels.append(MAC)
            mac_queued += 1
        else:
            labels.append(HOSTED)
            hosted_queued += 1
    return labels


def decide(env, now, fetch):
    busy, hosted_queued, mac_queued = None, 0, 0
    if takes_macs(env) and count_of(env) > 0:
        try:
            busy, hosted_queued, mac_queued = hosted_busy(env.get("REPO", ""), fetch)
        except Exception as error:
            print(f"route: hosted count unavailable, all hosted ({error})", file=sys.stderr)
    labels = route(env, now, busy, hosted_queued, mac_queued)
    idle = sum(fresh(env.get("IDLE") or "", now))
    queues = f"queued hosted {hosted_queued}, queued Macs {mac_queued}"
    print(f"route: hosted busy {busy}, {queues}, idle Macs {idle} -> {labels}", file=sys.stderr)
    return labels


def github(env):
    base = env.get("GITHUB_API_URL", "https://api.github.com")
    token = env.get("GITHUB_TOKEN", "")

    def fetch(path):
        if not token:
            raise RuntimeError("no GITHUB_TOKEN")
        request = urllib.request.Request(base + path, headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        })
        with urllib.request.urlopen(request, timeout=20) as reply:
            return json.load(reply)

    return fetch


if __name__ == "__main__":
    print(json.dumps(decide(os.environ, int(time.time()), github(os.environ))))
