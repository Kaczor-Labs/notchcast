#!/usr/bin/env python3
"""Shadow of the PR mac job's overflow route (#1330): print where it would run; change and fail nothing."""
import json
import os
import subprocess
import sys

HOSTED_SLOTS = 5
MBP_LABEL = "notchcast-mbp"
# shortcut: the workflow token cannot list runners (admin only), so an offline MBP runner counts idle; PR B needs one.
MBP_RUNNERS = 2


def gh(path):
    return json.loads(subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True, timeout=10).stdout)


def running_jobs(api, owner):
    """In-progress jobs of the owner's public repositories: the workflow token reads no private one."""
    for repo in api(f"orgs/{owner}/repos?type=public&per_page=100"):
        runs = api(f"repos/{repo['full_name']}/actions/runs?status=in_progress&per_page=100")["workflow_runs"]
        for run in runs:
            yield from (job for job in api(f"repos/{repo['full_name']}/actions/runs/{run['id']}/jobs?per_page=100")["jobs"]
                        if job["status"] == "in_progress")


def hosted_mac(job):
    return job.get("runner_group_name") == "GitHub Actions" and any(
        label.startswith(("macos", "xcode")) for label in job["labels"])


def decide(api, owner, event, fork):
    try:
        jobs = list(running_jobs(api, owner))
    except Exception as error:  # any API failure keeps the job hosted, as today
        return f"would=hosted busy=?/{HOSTED_SLOTS} mbp_idle=? reason={type(error).__name__}: {str(error)[:120]}"
    busy = sum(map(hosted_mac, jobs))
    idle = max(0, MBP_RUNNERS - sum(MBP_LABEL in job["labels"] for job in jobs))
    overflow = event == "pull_request" and not fork and busy >= HOSTED_SLOTS and idle > 0
    return f"would={'mbp' if overflow else 'hosted'} busy={busy}/{HOSTED_SLOTS} mbp_idle={idle}"


if __name__ == "__main__":
    line = decide(gh, os.environ.get("GITHUB_REPOSITORY_OWNER", ""), os.environ.get("EVENT", ""),
                  os.environ.get("FORK") == "true")
    print(f"mac-route shadow: {line}", flush=True)
    sys.exit(0)
