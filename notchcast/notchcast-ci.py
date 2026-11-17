#!/usr/bin/env python3
"""Prove a Notchcast branch's harnesses on GitHub's macOS runners instead of the local build queue.

    python3 notchcast/notchcast-ci.py --repo DIR [--no-push | --run ID] [--max-wait SECONDS]

Moved here from old Chad's bin/ at the Chad v2 cutover.

Each call ends within about 100 s, because a Bash call past 120 s moves to the background: --max-wait (default 100)
bounds every wait and every gh and git call below (a push past it is an error); pass a longer one only from a background shell. Out of time before a run is found or
dispatched it prints `WAITING (not dispatched); rerun: ... --no-push`, after it `PENDING <url> at <sha12>; rerun: ...
--run <id>`, and exits 3: run the printed rerun command. --run ID skips the push, the lookup, the cap and the
dispatch and polls that run (its headSha still checked against HEAD) to the usual verdict; a run of any workflow but
main-harnesses.yml is an error.

First, refuse a HEAD that tracks a `*.pyc` or `__pycache__/` path, whatever its content, and a checkout whose
core.hooksPath is not notchcast/githooks (its pushes would skip the repo's pre-push hook). Then, in order: (1) run exactly
`git -C DIR push -u origin HEAD:refs/heads/<branch>` without LEFTHOOK* and GIT_CONFIG* variables (no force; a
detached HEAD and main are refused) and stop when it fails; with --no-push, refuse unless origin's branch already
equals local HEAD. (2) Find the push-triggered main-harnesses.yml run whose headSha is HEAD with
`gh run list --commit <sha> --event push`, every 15 s for up to 90 s (stopping early enough to dispatch within
--max-wait); when one appears, skip to (5), unless it already completed with a conclusion that proves nothing
(below), then go straight to (3). (3) None appeared, so the branch's workflow file predates the push trigger, or
its run proved nothing: wait while MAX_DISPATCHES or more of the latest 50 workflow_dispatch runs of main-harnesses.yml are not completed
(GitHub itself caps concurrent macOS jobs and queues the rest FIFO; this cap only keeps our dispatches from flooding
that queue ahead of PR and Sync runs), with one API call every 60 s, printing one line per change. (4) Dispatch
main-harnesses.yml on the branch and use the workflow_run_id and html_url its response carries (never "the latest
run"); a response without workflow_run_id is an error. (5) Poll the run with one `gh run view`
every 60 s until it completes, then print the last ~40 lines of the failing step's log on a failure and one final line:
`PASS|FAIL <html_url> at <sha12> harnesses: <list>` (sha12 is the run's headSha; the list is the "Changed harnesses"
step's output; `PASS (no harnesses selected) <html_url> at <sha12>` when it selected none, `harnesses: unknown` when
the log cannot be read). A conclusion other than success or failure (cancelled, e.g. superseded in the workflow's
concurrency group; timed_out; skipped) proves nothing: `NOPROOF <html_url> conclusion <c>; rerun`.
The account's API budget is shared: a poll that hits "API rate limit exceeded" prints
`notchcast-ci: GitHub API rate limit; waiting until <HH:MM> UTC`, sleeps until the reset and retries; before the
dispatch, fewer than 500 calls left likewise waits for the reset (`notchcast-ci: N API calls left (<500); waiting ...`).

Exit 0: the run passed. 1: the run failed. 2: usage or infrastructure error (gh, git, a failed push, no push
to prove), a NOPROOF run, or a run whose headSha is not the HEAD this started at (the branch moved; the verdict is
still printed). 3: still pending; rerun the printed command. Overrides for tests: NOTCHCAST_CI_POLL (seconds between
polls), NOTCHCAST_CI_PUSH_WAIT (seconds to look for the push run), NOTCHCAST_CI_MAX_DISPATCHES.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

# macOS capacity is 7 concurrent jobs: GitHub's 5 hosted (plan cap) plus self-hosted runners mba-1 and mba-2;
# 3 dispatches fit 5 slots, so 5 fit 7-8. Waiting at this many keeps leads from flooding the queue ahead of PR and Sync runs.
MAX_DISPATCHES = 5
REPO = re.search(r"^FORK_REPO=(.+)$", (Path(__file__).resolve().parent / "config.env").read_text(), re.M)[1]
WORKFLOW = "main-harnesses.yml"
HOOKS = "notchcast/githooks"
STEP = "Changed harnesses"
FAILED_LOG_LINES = 40
MIN_API_CALLS = 500  # the hourly budget is shared with every lead's gh; never dispatch into its last calls
PUSH_RUN_POLL = 15
HARNESS = re.compile(r"[\w.+-]+")


class Infra(Exception):
    pass


class OutOfTime(Exception):
    pass


deadline = float("inf")


def nap(seconds):
    """time.sleep that refuses to run past --max-wait."""
    if time.time() + seconds > deadline:
        raise OutOfTime
    time.sleep(seconds)


def time_left():
    """Seconds a child process may take before --max-wait runs out (None without one)."""
    left = deadline - time.time()
    if left <= 0:
        raise OutOfTime
    return None if left == float("inf") else left


def run(*cmd):
    try:
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=time_left())
    except subprocess.TimeoutExpired:
        raise OutOfTime from None
    if result.returncode:
        raise Infra(f"{' '.join(cmd[:4])} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout.strip()


def git(repo, *args):
    return run("git", "-C", repo, *args)


def max_dispatches():
    return int(os.environ.get("NOTCHCAST_CI_MAX_DISPATCHES", MAX_DISPATCHES))


def rate_limit(field):
    return int(run("gh", "api", "rate_limit", "--jq", f".resources.core.{field}"))  # not counted by GitHub


def sleep_until_reset(reason):
    reset = rate_limit("reset")
    print(f"notchcast-ci: {reason}; waiting until {time.strftime('%H:%M', time.gmtime(reset))} UTC", flush=True)
    nap(max(0, reset + 5 - time.time()))


def patient_gh(*args):
    """gh, sleeping out the account's API rate limit instead of failing on it."""
    while True:
        try:
            return run("gh", *args)
        except Infra as error:
            if "API rate limit exceeded" not in str(error):
                raise
        sleep_until_reset("GitHub API rate limit")


def wait_for_api_budget():
    while (left := rate_limit("remaining")) < MIN_API_CALLS:
        sleep_until_reset(f"{left} API calls left (<{MIN_API_CALLS})")


def poll_seconds():
    return float(os.environ.get("NOTCHCAST_CI_POLL", "60"))


def outstanding_dispatches():
    runs = json.loads(patient_gh("api", f"repos/{REPO}/actions/workflows/{WORKFLOW}/runs"
                                 "?event=workflow_dispatch&per_page=50"))
    return sum(r["status"] != "completed" for r in runs["workflow_runs"])


def wait_for_capacity(cap):
    last = None
    while (busy := outstanding_dispatches()) >= cap:
        if busy != last:
            print(f"notchcast-ci: {busy} harness dispatch(es) queued or running, cap {cap}; waiting", flush=True)
            last = busy
        nap(poll_seconds())


def finished_run(run_id):
    while True:
        state = json.loads(patient_gh("run", "view", str(run_id), "-R", REPO, "--json", "status,conclusion,headSha"))
        if state["status"] == "completed":
            return state
        nap(poll_seconds())


def push(repo, branch):
    refspec = ["origin", f"HEAD:refs/heads/{branch}"]
    env = {key: value for key, value in os.environ.items() if not key.startswith(("LEFTHOOK", "GIT_CONFIG"))}
    try:
        failed = subprocess.run(["git", "-C", repo, "push", "-u", *refspec], env=env, timeout=time_left()).returncode
    except subprocess.TimeoutExpired:
        raise Infra(f"git push origin HEAD:refs/heads/{branch} ran past --max-wait; nothing dispatched") from None
    if failed:
        raise Infra(f"git push origin HEAD:refs/heads/{branch} failed; nothing dispatched")


def push_run(head):
    """The push-triggered run of head as (run_id, url), or None when none that can prove it appears in time."""
    interval = min(PUSH_RUN_POLL, poll_seconds())
    give_up = min(time.time() + float(os.environ.get("NOTCHCAST_CI_PUSH_WAIT", "90")), deadline - interval)
    while True:
        runs = json.loads(patient_gh("run", "list", "-R", REPO, "-w", WORKFLOW, "--commit", head, "--event", "push",
                                     "--json", "databaseId,url,status,conclusion"))
        if runs:
            live = [r for r in runs if r["status"] != "completed" or r["conclusion"] in ("success", "failure")]
            return (live[0]["databaseId"], live[0]["url"]) if live else None  # no second push run will come
        if time.time() >= give_up:
            return None
        nap(interval)


def dispatch(branch):
    text = run("gh", "api", "-X", "POST", f"repos/{REPO}/actions/workflows/{WORKFLOW}/dispatches",
               "-f", f"ref={branch}", "-F", "return_run_details=true")
    body = json.loads(text) if text else {}
    if not body.get("workflow_run_id"):
        raise Infra(f"dispatch response has no workflow_run_id: {text or '(empty)'}")
    return body["workflow_run_id"], body.get("html_url") or f"https://github.com/{REPO}/actions/runs/{body['workflow_run_id']}"


def selected_harnesses(run_id):
    """The names the "Changed harnesses" step printed, or None when its log or the step cannot be read."""
    try:
        log = run("gh", "run", "view", str(run_id), "-R", REPO, "--log")
    except Infra:
        return None
    steps = []  # [is ours, lines outside groups]; gh may label every line UNKNOWN STEP
    key = in_group = None
    for line in log.splitlines():
        parts = line.lstrip(chr(0xFEFF)).split("\t", 2)
        if len(parts) < 3:
            continue
        text = parts[2].partition(" ")[2].strip()  # drop the timestamp
        if parts[:2] != key or text.startswith("##[group]Run "):
            key, in_group = parts[:2], False
            steps.append([parts[1] == STEP, []])
        if text.startswith("##[group]"):
            in_group = True
        elif text.startswith("##[endgroup]"):
            in_group = False
        elif in_group:
            steps[-1][0] |= "changed-harnesses.sh" in text
        else:
            steps[-1][1].append(text)
    if not any(is_ours for is_ours, _ in steps):
        return None
    return [text for is_ours, lines in steps if is_ours for text in lines if HARNESS.fullmatch(text)]


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", required=True, help="the Notchcast checkout")
    parser.add_argument("--no-push", action="store_true", help="prove the branch as origin already has it")
    parser.add_argument("--run", type=int, help="poll this already dispatched run instead of dispatching")
    parser.add_argument("--max-wait", type=float, default=100, help="seconds this call may wait in all (default 100)")
    args = parser.parse_args(argv)
    global deadline
    deadline = time.time() + args.max_wait
    try:
        return prove(args)
    except Infra as error:
        print(f"notchcast-ci: {error}", file=sys.stderr)
        return 2
    except OutOfTime:
        print("notchcast-ci: --max-wait ran out while reading the checkout; nothing pushed or dispatched",
              file=sys.stderr)
        return 2


def prove(args):
    repo = git(args.repo, "rev-parse", "--show-toplevel")
    branch = subprocess.run(["git", "-C", repo, "symbolic-ref", "--short", "-q", "HEAD"], text=True,
                            capture_output=True).stdout.strip()
    if branch in ("", "main"):
        raise Infra(f"needs a checked-out branch other than main (HEAD is {branch or 'detached'})")
    head = git(repo, "rev-parse", "HEAD")
    refuse_unsafe_checkout(repo)
    rerun = f"python3 {repo}/notchcast/notchcast-ci.py --repo {repo}"
    if args.run:
        run_id, url = args.run, f"https://github.com/{REPO}/actions/runs/{args.run}"
    else:
        try:
            run_id, url = start_run(args, repo, branch, head)
        except OutOfTime:
            print(f"WAITING (not dispatched); rerun: {rerun} --no-push")
            return 3
    try:
        if args.run:
            path = patient_gh("api", f"repos/{REPO}/actions/runs/{run_id}", "--jq", ".path")
            if path.split("@")[0] != f".github/workflows/{WORKFLOW}":
                raise Infra(f"run {run_id} is {path or 'of no workflow file'}, not {WORKFLOW}; it proves no harness")
        return verdict(run_id, url, finished_run(run_id), head)
    except OutOfTime:
        print(f"PENDING {url} at {head[:12]}; rerun: {rerun} --run {run_id}")
        return 3


def refuse_unsafe_checkout(repo):
    """A tracked Python cache at HEAD, or a clone whose pushes skip the repo's pre-push hook, is refused."""
    caches = [path for path in git(repo, "ls-tree", "-r", "--name-only", "HEAD").splitlines()
              if path.endswith(".pyc") or "__pycache__" in path.split("/")]
    if caches:
        raise Infra(f"HEAD tracks Python caches ({', '.join(caches[:5])}); git rm --cached them first")
    hooks = subprocess.run(["git", "-C", repo, "config", "--get", "core.hooksPath"], text=True,
                           capture_output=True).stdout.strip()
    if hooks != HOOKS:
        raise Infra(f"core.hooksPath is {hooks or 'unset'}; run `git -C {repo} config core.hooksPath {HOOKS}`")


def start_run(args, repo, branch, head):
    """Push (unless --no-push), then the push's run, else wait for capacity and budget and dispatch: (run_id, url)."""
    cap = max_dispatches()
    if args.no_push:
        remote = git(repo, "ls-remote", "origin", f"refs/heads/{branch}").split()
        if remote[:1] != [head]:
            raise Infra(f"--no-push: origin/{branch} is {remote[0][:12] if remote else 'missing'} but HEAD is {head[:12]}; "
                        "run this without --no-push to push it")
    else:
        push(repo, branch)
    if found := push_run(head):
        print(f"notchcast-ci: push run {found[1]}; watching", flush=True)
        return found
    wait_for_capacity(cap)
    wait_for_api_budget()
    run_id, url = dispatch(branch)
    print(f"notchcast-ci: dispatched {url}; watching", flush=True)
    return run_id, url


def verdict(run_id, url, state, head):
    if state["conclusion"] not in ("success", "failure"):
        print(f"NOPROOF {url} conclusion {state['conclusion']}; rerun")
        return 2
    passed = state["conclusion"] == "success"
    sha = state["headSha"][:12]
    names = selected_harnesses(run_id)
    if not passed:
        try:
            failed = run("gh", "run", "view", str(run_id), "-R", REPO, "--log-failed").splitlines()
        except Infra as error:
            failed = [f"(failed-step log unavailable: {error})"]
        print("\n".join(failed[-FAILED_LOG_LINES:]))
    label = "PASS" if passed else "FAIL"
    if names == []:
        print(f"{label} (no harnesses selected) {url} at {sha}")
    else:
        print(f"{label} {url} at {sha} harnesses: {', '.join(names) if names else 'unknown'}")
    if state["headSha"] != head:
        print(f"notchcast-ci: the branch moved: the run tested {sha} but HEAD was {head[:12]}", file=sys.stderr)
        return 2
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
