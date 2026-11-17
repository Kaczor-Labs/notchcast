#!/usr/bin/env python3
"""Plan a main snapshot, wait for its gate, or check it is still current, without changing refs."""
import json
import os
import math
import sys
import time
from datetime import datetime, timedelta, timezone

from ci import config, output, run, version_key


GATE = timedelta(minutes=50)


def revision(tag):
    stamp = tag.rsplit(".snapshot.", 1)[1]
    return datetime.strptime(stamp, "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)


def latest_snapshot(releases, other_than=None):
    tags = [r["tagName"] for r in releases
            if not r["isDraft"] and ".snapshot." in r["tagName"] and r["tagName"] != other_than]
    return max(tags, key=revision, default=None)


def plan(releases, main, commit, now, event, skip_gate=False):
    start = now
    latest = latest_snapshot(releases)
    if latest:
        if commit(latest) == main:
            return {"error" if event == "workflow_dispatch" else "skip": f"unchanged main {main}"}
        opens = revision(latest) + GATE
        if now < opens and not skip_gate:
            reason = f"50-minute gate closed for main {main}; opens {opens:%Y-%m-%d %H:%M:%S} UTC"
            if event == "workflow_dispatch":
                return {"closed": reason}
            start = opens
    mirrors = [r["tagName"] for r in releases if not r["isDraft"] and version_key(r["tagName"])]
    base = max(mirrors, key=version_key)
    return {"tag": f"{base}.snapshot.{start:%Y%m%d%H%M%S}"}


def stale(releases, tag, main, current, now, skip_gate=False):
    if current != main:
        return {"skip": f"main moved from {main} to {current}"}
    if now < revision(tag):
        return {"error": f"{tag} reached publish before its revision time"}
    latest = latest_snapshot(releases, other_than=tag)
    if latest and not skip_gate and revision(tag) < revision(latest) + GATE:
        return {"error": f"{latest} is within 50 minutes of {tag}"}
    return {}


def main(command=None):
    if command == "wait":
        delay = (revision(os.environ["TAG"]) - datetime.now(timezone.utc)).total_seconds()
        if delay > 0:
            print(f"Waiting {math.ceil(delay)} seconds for the snapshot gate", flush=True)
            time.sleep(delay)
        return 0
    repo = config()["FORK_REPO"]
    run("git", "fetch", "--force", "--tags", "origin", "main")
    sha = run("git", "rev-parse", "FETCH_HEAD")
    pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"))
    releases = [{"tagName": r["tag_name"], "isDraft": r["draft"]} for page in pages for r in page]
    now = datetime.now(timezone.utc)
    skip_gate = os.environ.get("SKIP_GATE") == "true"
    if command == "check":
        result = stale(releases, os.environ["TAG"], os.environ["MAIN"], sha, now, skip_gate)
    else:
        result = plan(releases, sha, lambda t: run("git", "rev-parse", f"refs/tags/{t}^{{commit}}"),
                      now, os.environ["GITHUB_EVENT_NAME"], skip_gate)
    if "error" in result:
        print(f"::error::Snapshot skipped: {result['error']}")
        return 1
    if "closed" in result:
        print(f"::notice::Snapshot skipped: {result['closed']}")
        return 0
    if "skip" in result:
        print(f"{'::notice::' if command == 'check' else ''}Snapshot skipped: {result['skip']}")
        return 0
    if command == "check":
        output(publish="true")
        return 0
    tag = result["tag"]
    output(tag=tag, version=tag[1:], build=os.environ["GITHUB_RUN_NUMBER"], main=sha)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(*sys.argv[1:2]))
