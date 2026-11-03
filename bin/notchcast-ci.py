#!/usr/bin/env python3
"""Notchcast CI helper, run by .github/workflows/sync.yml from a checkout of the notchcast branch.

    notchcast-ci.py plan                 decide what this run builds; writes job outputs
    notchcast-ci.py apply <tree> <base>  apply patches/series on <base> in the upstream checkout <tree>
    notchcast-ci.py app-info <tag> <dir> name, bundle id, version and build of upstream's release zip

Failures are remembered as refs/notchcast-failed/<kind>-<input>-<branch tree>, so a failed upstream
commit or tag is retried only when upstream moves or this branch changes.
"""
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

QUEUE = Path(__file__).resolve().parent.parent
PATCHES = QUEUE / "patches"
GIT_ID = {
    "GIT_AUTHOR_NAME": "Notchcast", "GIT_AUTHOR_EMAIL": "notchcast@users.noreply.github.com",
    "GIT_COMMITTER_NAME": "Notchcast", "GIT_COMMITTER_EMAIL": "notchcast@users.noreply.github.com",
}


def config():
    values = {}
    for line in (QUEUE / "config.env").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key] = value.strip().strip('"')
    return values


def run(*cmd, cwd=QUEUE, env=None):
    return subprocess.run(cmd, cwd=cwd, env=dict(os.environ, **(env or {})), text=True,
                          check=True, capture_output=True).stdout.strip()


def ls_remote(url, *patterns):
    refs = {}
    for line in run("git", "ls-remote", url, *patterns).splitlines():
        sha, ref = line.split("\t")
        refs[ref] = sha
    return refs


TAG_RE = re.compile(r"v(\d+)\.(\d+)\.(\d+)(?:-[a-z]+\.(\d+))?")


def version_key(tag):
    """v0.12.6-beta.130 -> ((0, 12, 6), 0, 130); a stable release sorts after its betas; None if unparsable."""
    m = TAG_RE.fullmatch(tag)
    if not m:
        return None
    nums = tuple(int(x) for x in m.group(1, 2, 3))
    return (nums, 1, 0) if m.group(4) is None else (nums, 0, int(m.group(4)))


def output(**values):
    with open(os.environ["GITHUB_OUTPUT"], "a") as out:
        for key, value in values.items():
            out.write(f"{key}={value}\n")
            print(f"{key}={value}")


def plan():
    cfg = config()
    upstream = f"https://github.com/{cfg['UPSTREAM_REPO']}.git"
    fork = f"https://github.com/{cfg['FORK_REPO']}.git"
    patches_tree = run("git", "rev-parse", "HEAD:patches")
    branch_tree = run("git", "rev-parse", "HEAD^{tree}")
    upstream_main = ls_remote(upstream, "refs/heads/main")["refs/heads/main"]
    upstream_tags = {r.removeprefix("refs/tags/"): sha for r, sha in ls_remote(upstream, "refs/tags/*").items()
                     if not r.endswith("^{}")}
    origin = ls_remote(fork)
    failed = {r.removeprefix("refs/notchcast-failed/") for r in origin if r.startswith("refs/notchcast-failed/")}

    origin_main = origin.get("refs/heads/main", "")
    main_key = f"main-{upstream_main}-{branch_tree}"
    message = ""
    if origin_main:
        run("git", "fetch", "-q", "--depth=1", fork, "refs/heads/main")
        message = run("git", "log", "-1", "--format=%B", "FETCH_HEAD")
    current = f"Notchcast-Upstream: {upstream_main}" in message and f"Notchcast-Queue: {patches_tree}" in message
    if current:
        print(f"main: up to date (upstream {upstream_main[:10]}, patches {patches_tree[:10]})")
    elif main_key in failed:
        print(f"main: {main_key} already failed; waiting for upstream or this branch to change")
    else:
        print(f"main: rebuild on upstream {upstream_main[:10]} with patches {patches_tree[:10]}")

    ours = {r["tagName"] for r in json.loads(run(
        "gh", "release", "list", "-R", cfg["FORK_REPO"], "-L", "100", "--json", "tagName"))}
    theirs = json.loads(run("gh", "release", "list", "-R", cfg["UPSTREAM_REPO"], "-L", "30",
                            "--json", "tagName,name,isDraft,isPrerelease"))
    baseline = version_key(cfg["BASELINE_TAG"])
    releases = []
    for r in sorted((r for r in theirs if version_key(r["tagName"])), key=lambda r: version_key(r["tagName"])):
        tag = r["tagName"]
        if r["isDraft"] or tag in ours or tag not in upstream_tags or version_key(tag) < baseline:
            continue
        if f"release-{tag}-{branch_tree}" in failed:
            print(f"release {tag}: already failed with this branch; skipped")
            continue
        print(f"release {tag}: mirror")
        releases.append({"tag": tag, "title": r["name"], "prerelease": r["isPrerelease"]})

    output(main="false" if current or main_key in failed else "true", upstream_main=upstream_main,
           queue_commit=run("git", "rev-parse", "HEAD"),
           origin_main=origin_main, main_key=main_key, branch_tree=branch_tree, patches_tree=patches_tree,
           releases=json.dumps(releases, separators=(",", ":")))


def apply(tree, base):
    """Apply the series on base in tree; with base 'main' also add the generated-main commit."""
    tree = Path(tree)
    commit = run("git", "rev-parse", "HEAD", cwd=tree)
    date = run("git", "show", "-s", "--format=%cI", commit, cwd=tree)
    env = dict(GIT_ID, GIT_COMMITTER_DATE=date, GIT_AUTHOR_DATE=date)
    for line in (PATCHES / "series").read_text().splitlines():
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        path = PATCHES / entry
        print(f"apply {entry}", flush=True)
        if entry.endswith(".patch"):
            subprocess.run(["git", "am", "-3", "--keep-cr", "--committer-date-is-author-date", str(path)],
                           cwd=tree, env=dict(os.environ, **env), check=True)
        elif entry.endswith(".sh"):
            subprocess.run(["bash", str(path)], cwd=tree, env=dict(os.environ, **env), check=True)
            subject = next(l[2:] for l in path.read_text().splitlines()[1:] if l.startswith("# "))
            run("git", "add", "-A", cwd=tree)
            run("git", "commit", "-q", "--allow-empty", "-m", subject, cwd=tree, env=env)
        else:
            sys.exit(f"unknown series entry {entry}")
    if base == "main":
        patches_tree = run("git", "rev-parse", "HEAD:patches")
        run("git", "commit", "-q", "--allow-empty", "-m",
            f"Notchcast: generated main\n\nNotchcast-Upstream: {commit}\nNotchcast-Queue: {patches_tree}",
            cwd=tree, env=env)
    print(run("git", "log", "--oneline", f"{commit}..HEAD", cwd=tree))


def app_info(tag, out_dir):
    """Name, bundle id, version and build from upstream's own thin zip, so our build matches it."""
    cfg = config()
    with tempfile.TemporaryDirectory() as tmp:
        run("gh", "release", "download", tag, "-R", cfg["UPSTREAM_REPO"], "-D", tmp, "-p", "Tinycast-[0-9]*.zip")
        zips = [z for z in Path(tmp).glob("Tinycast-*.zip") if "-Universal-" not in z.name]
        if len(zips) != 1:
            sys.exit(f"expected one thin zip in upstream {tag}, found {[z.name for z in zips]}")
        listing = run("zipinfo", "-1", str(zips[0])).splitlines()
        plist_path = next(l for l in listing if l.count("/") == 2 and l.endswith(".app/Contents/Info.plist"))
        info = plistlib.loads(subprocess.run(["unzip", "-p", str(zips[0]), plist_path],
                                             capture_output=True, check=True).stdout)
    version = info["CFBundleShortVersionString"]
    if f"v{version}" != tag:
        sys.exit(f"upstream zip says version {version}, tag is {tag}")
    body = json.loads(run("gh", "release", "view", tag, "-R", cfg["UPSTREAM_REPO"], "--json", "body"))["body"]
    Path(out_dir, "upstream-notes.md").write_text(body)
    output(name=info["CFBundleName"], bundle_id=info["CFBundleIdentifier"], version=version,
           build=info["CFBundleVersion"])


if __name__ == "__main__":
    command, args = sys.argv[1], sys.argv[2:]
    {"plan": plan, "apply": apply, "app-info": app_info}[command](*args)
