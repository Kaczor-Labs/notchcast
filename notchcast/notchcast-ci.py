#!/usr/bin/env python3
"""Prove a Notchcast branch's harnesses on GitHub's macOS runners instead of the local build queue.

    python3 notchcast/notchcast-ci.py --repo DIR --keeper [--no-push | --run ID] [--max-wait SECONDS]

Keeper-only: Main harnesses is one lane for every branch (one run going, one pending), so without --keeper this
pushes and dispatches nothing and exits 2.

Each call ends within about 100 s, because a Bash call past 120 s moves to the background: --max-wait (default 100)
bounds every wait and every gh and git call below (a push past it is an error); pass a longer one only from a background shell. Out of time before it
dispatches it prints `WAITING (not dispatched); rerun: ... --no-push`, after it `PENDING <url> at <sha12>; rerun: ...
--run <id>`, and exits 3: run the printed rerun command. --run ID skips the push, the queue check and the dispatch and polls that run (its headSha still checked against HEAD) to the usual verdict; a run of any workflow but
main-harnesses.yml is an error.

First, refuse a HEAD that tracks a `*.pyc` or `__pycache__/` path, whatever its content, and a checkout whose
core.hooksPath is not notchcast/githooks (its pushes would skip the repo's pre-push hook). Then, in order: (1) run exactly
`git -C DIR push -u origin HEAD:refs/heads/<branch>` without LEFTHOOK* and GIT_CONFIG* variables (no force; a
detached HEAD and main are refused) and stop when it fails; with --no-push, refuse unless origin's branch already
equals local HEAD. Main harnesses runs only when dispatched. (2) When one of the latest 50 workflow_dispatch runs of
main-harnesses.yml has not started (queued, pending, waiting or requested), dispatch nothing, print `QUEUED <url>: one
Main harnesses run already waits; rerun when it starts` and exit 4: a second waiting run would cancel the first in the
workflow's concurrency group. A run in progress does not block; the new run waits behind it. (3) Dispatch
main-harnesses.yml on the branch and use the workflow_run_id and html_url its response carries (never "the latest
run"); a response without workflow_run_id is an error. (4) Poll the run every 60 s until it completes, reading its
check suite over GraphQL (its own hourly budget) and `gh run view` only where GraphQL cannot say; under RESERVE calls
left in the bucket a poll used, the wait stretches by RESERVE/left with jitter, up to the reset plus 0-120 s, and says
so (`notchcast-ci: N <bucket> calls left (<1500); next poll in S s`). Then print the last ~40 lines of the failing step's log on a failure and one final line:
`PASS|FAIL <html_url> at <sha12> harnesses: <list>` (sha12 is the run's headSha; the list is the "Changed harnesses"
step's output; `PASS (no harnesses selected) <html_url> at <sha12>` when it selected none, `harnesses: unknown` when
the log cannot be read). A conclusion other than success or failure (cancelled, e.g. superseded in the workflow's
concurrency group; timed_out; skipped) proves nothing: `NOPROOF <html_url> conclusion <c>; rerun`.
A run whose log shows a skipped harness (a self-hosted runner's NOTCHCAST_RUNNER_SKIP_TESTS, or a hosted-only one)
proves nothing for it: a success prints `NOPROOF <html_url> at <sha12> skipped harnesses: <list>; rerun on a hosted
runner` and exits 2, a failure appends `; skipped: <list>` to its FAIL line.
The account's API budget is shared: a poll that hits "API rate limit exceeded" prints
`notchcast-ci: GitHub API rate limit; waiting until <HH:MM> UTC`, sleeps until the reset plus a random 0-120 s, so
pollers do not wake together, and retries; before the dispatch, fewer than 500 calls left likewise waits
(`notchcast-ci: N API calls left (<500); waiting ...`).

Exit 0: the run passed. 1: the run failed. 2: usage or infrastructure error (gh, git, a failed push, no push
to prove), a NOPROOF run, or a run whose headSha is not the HEAD this started at (the branch moved; the verdict is
still printed), or no --keeper. 3: still pending; rerun the printed command. 4: QUEUED, nothing dispatched; rerun once
the waiting run starts. Overrides for tests: NOTCHCAST_CI_POLL (seconds between polls) and
NOTCHCAST_CI_CLOCK=virtual (waits advance a counter instead of sleeping; a child process gets the virtual time
left as its real timeout).
"""
import argparse
import json
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import time

REPO = re.search(r"^FORK_REPO=(.+)$", (Path(__file__).resolve().parent / "config.env").read_text(), re.M)[1]
WORKFLOW = "main-harnesses.yml"
KEEPER_ONLY = "Main harnesses is Keeper-only: push your branch (git push) and ask your Keeper for the harness proof"
NOT_STARTED = ("queued", "pending", "waiting", "requested")
HOOKS = "notchcast/githooks"
STEP = "Changed harnesses"
FAILED_LOG_LINES = 40
MIN_API_CALLS = 500  # the hourly budget is shared with every lead's gh; never dispatch into its last calls
RESERVE = 1500  # calls left for land.sh and the Keepers: under it a poll waits longer, so pollers spread to the reset
WAKE_JITTER = 120  # pollers that all slept to one reset would empty the new budget again on waking together
RATE_LIMITED = re.compile(r"rate limit (?:already )?exceeded", re.I)
RUN_QUERY = "query($id: ID!) { node(id: $id) { ... on WorkflowRun { checkSuite { status conclusion commit { oid } } } } }"
HARNESS = re.compile(r"[\w.+-]+")
# test-harnesses.sh's two skip lines: a runner's own NOTCHCAST_RUNNER_SKIP_TESTS, and a hosted-only harness.
SKIPPED = re.compile(r"(?:##\[notice\]|::notice::)SKIPPED on this runner: ([\w.+-]+)|\bSKIPPED ([\w.+-]+): hosted-only:")


class Infra(Exception):
    pass


class OutOfTime(Exception):
    pass


class Queued(Exception):
    pass


deadline = float("inf")
VIRTUAL_CLOCK = os.environ.get("NOTCHCAST_CI_CLOCK") == "virtual"
virtual_now = time.time()


def now():
    return virtual_now if VIRTUAL_CLOCK else time.time()


def nap(seconds):
    """time.sleep that refuses to run past --max-wait."""
    global virtual_now
    if now() + seconds > deadline:
        raise OutOfTime
    if VIRTUAL_CLOCK:
        virtual_now += seconds
    else:
        time.sleep(seconds)


def time_left():
    """Seconds a child process may take before --max-wait runs out (None without one)."""
    left = deadline - now()
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


def budget(bucket):
    """(calls left, reset epoch) of one rate-limit bucket, core (REST) or graphql; reading it is not counted."""
    left, reset = run("gh", "api", "rate_limit", "--jq", f'.resources.{bucket} | "\\(.remaining) \\(.reset)"').split()
    return int(left), int(reset)


def sleep_until_reset(reason, bucket="core", reset=None):
    reset = budget(bucket)[1] if reset is None else reset
    print(f"notchcast-ci: {reason}; waiting until {time.strftime('%H:%M', time.gmtime(reset))} UTC", flush=True)
    nap(max(0, reset - now()) + random.uniform(0, WAKE_JITTER))


def patient_gh(*args, bucket="core"):
    """gh, sleeping out the account's API rate limit instead of failing on it."""
    while True:
        try:
            return run("gh", *args)
        except Infra as error:
            if not RATE_LIMITED.search(str(error)):
                raise
        sleep_until_reset("GitHub API rate limit", bucket)


def wait_for_api_budget():
    while (state := budget("core"))[0] < MIN_API_CALLS:
        sleep_until_reset(f"{state[0]} API calls left (<{MIN_API_CALLS})", reset=state[1])


def poll_seconds():
    return float(os.environ.get("NOTCHCAST_CI_POLL", "60"))


def poll_wait(bucket):
    """The pause before the next poll: the usual one, stretched under RESERVE so every poller leaves the reserve be."""
    left, reset = budget(bucket)
    if left >= RESERVE:
        return poll_seconds()
    to_reset = max(0, reset - now())
    stretched = poll_seconds() * RESERVE / max(left, 1)
    wait = to_reset + random.uniform(0, WAKE_JITTER) if stretched >= to_reset else stretched * random.uniform(1, 1.25)
    print(f"notchcast-ci: {left} {bucket} calls left (<{RESERVE}); next poll in {wait:.0f} s", flush=True)
    return wait


def refuse_while_one_waits():
    runs = json.loads(patient_gh("api", f"repos/{REPO}/actions/workflows/{WORKFLOW}/runs"
                                 "?event=workflow_dispatch&per_page=50"))
    for waiting in runs["workflow_runs"]:
        if waiting["status"] in NOT_STARTED:
            raise Queued(waiting["html_url"])


def graphql_state(node_id):
    """The run's state from its check suite over GraphQL (its own budget), or None where GraphQL cannot say."""
    try:
        data = json.loads(patient_gh("api", "graphql", "-f", f"query={RUN_QUERY}", "-f", f"id={node_id}",
                                     bucket="graphql"))
    except (Infra, ValueError):
        return None
    suite = ((data.get("data") or {}).get("node") or {}).get("checkSuite")
    if not suite:
        return None
    return {"status": suite["status"].lower(), "conclusion": (suite["conclusion"] or "").lower() or None,
            "headSha": suite["commit"]["oid"]}


def finished_run(run_id, node_id):
    while True:
        state = graphql_state(node_id) if node_id else None
        bucket = "graphql" if state else "core"
        if state is None:
            state = json.loads(patient_gh("run", "view", str(run_id), "-R", REPO, "--json", "status,conclusion,headSha"))
        if state["status"] == "completed":
            return state
        nap(poll_wait(bucket))


def push(repo, branch):
    refspec = ["origin", f"HEAD:refs/heads/{branch}"]
    env = {key: value for key, value in os.environ.items() if not key.startswith(("LEFTHOOK", "GIT_CONFIG"))}
    try:
        failed = subprocess.run(["git", "-C", repo, "push", "-u", *refspec], env=env, timeout=time_left()).returncode
    except subprocess.TimeoutExpired:
        raise Infra(f"git push origin HEAD:refs/heads/{branch} ran past --max-wait; nothing dispatched") from None
    if failed:
        raise Infra(f"git push origin HEAD:refs/heads/{branch} failed; nothing dispatched")


def dispatch(branch):
    text = run("gh", "api", "-X", "POST", f"repos/{REPO}/actions/workflows/{WORKFLOW}/dispatches",
               "-f", f"ref={branch}", "-F", "return_run_details=true")
    body = json.loads(text) if text else {}
    if not body.get("workflow_run_id"):
        raise Infra(f"dispatch response has no workflow_run_id: {text or '(empty)'}")
    return body["workflow_run_id"], body.get("html_url") or f"https://github.com/{REPO}/actions/runs/{body['workflow_run_id']}"


def run_log(run_id):
    try:
        return run("gh", "run", "view", str(run_id), "-R", REPO, "--log")
    except Infra:
        return None


def skipped_harnesses(log):
    """Harnesses the run's runner skipped (a runner list or hosted-only), in log order; a skip proves nothing."""
    return list(dict.fromkeys(a or b for a, b in SKIPPED.findall(log or "")))


def selected_harnesses(log):
    """The names the "Changed harnesses" step printed, or None when its log or the step cannot be read."""
    if log is None:
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
    parser.add_argument("--keeper", action="store_true", help="you are the Keeper, the only one who dispatches")
    parser.add_argument("--no-push", action="store_true", help="prove the branch as origin already has it")
    parser.add_argument("--run", type=int, help="poll this already dispatched run instead of dispatching")
    parser.add_argument("--max-wait", type=float, default=100, help="seconds this call may wait in all (default 100)")
    args = parser.parse_args(argv)
    if not args.keeper:
        print(KEEPER_ONLY, file=sys.stderr)
        return 2
    global deadline
    deadline = now() + args.max_wait
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
    rerun = f"python3 {repo}/notchcast/notchcast-ci.py --repo {repo} --keeper"
    if args.run:
        run_id, url = args.run, f"https://github.com/{REPO}/actions/runs/{args.run}"
    else:
        try:
            run_id, url = start_run(args, repo, branch, head)
        except OutOfTime:
            print(f"WAITING (not dispatched); rerun: {rerun} --no-push")
            return 3
        except Queued as waiting:
            print(f"QUEUED {waiting}: one Main harnesses run already waits; rerun when it starts")
            return 4
    try:
        info = json.loads(patient_gh("api", f"repos/{REPO}/actions/runs/{run_id}", "--jq", "{path, node_id}"))
        path = info.get("path") or ""
        if args.run and path.split("@")[0] != f".github/workflows/{WORKFLOW}":
            raise Infra(f"run {run_id} is {path or 'of no workflow file'}, not {WORKFLOW}; it proves no harness")
        return verdict(run_id, url, finished_run(run_id, info.get("node_id")), head)
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
    """Push (unless --no-push), refuse while a run waits, wait for budget, then dispatch: (run_id, url)."""
    if args.no_push:
        remote = git(repo, "ls-remote", "origin", f"refs/heads/{branch}").split()
        if remote[:1] != [head]:
            raise Infra(f"--no-push: origin/{branch} is {remote[0][:12] if remote else 'missing'} but HEAD is {head[:12]}; "
                        "run this without --no-push to push it")
    else:
        push(repo, branch)
    refuse_while_one_waits()
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
    log = run_log(run_id)
    names, skipped = selected_harnesses(log), skipped_harnesses(log)
    if not passed:
        try:
            failed = run("gh", "run", "view", str(run_id), "-R", REPO, "--log-failed").splitlines()
        except Infra as error:
            failed = [f"(failed-step log unavailable: {error})"]
        print("\n".join(failed[-FAILED_LOG_LINES:]))
    label = "PASS" if passed else "FAIL"
    if passed and skipped:
        print(f"NOPROOF {url} at {sha} skipped harnesses: {', '.join(skipped)}; rerun on a hosted runner")
        return 2
    if names == []:
        print(f"{label} (no harnesses selected) {url} at {sha}")
    else:
        print(f"{label} {url} at {sha} harnesses: {', '.join(names) if names else 'unknown'}"
              + (f"; skipped: {', '.join(skipped)}" if skipped else ""))
    if state["headSha"] != head:
        print(f"notchcast-ci: the branch moved: the run tested {sha} but HEAD was {head[:12]}", file=sys.stderr)
        return 2
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
