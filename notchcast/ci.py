#!/usr/bin/env python3
"""Notchcast CI helper, run by .github/workflows/sync.yml.

    ci.py plan                              decide what this run builds (conflicts are found here, on Linux)
    ci.py stage open|close <base> <upstream>  push the upstream diff for review and open its PR, or close that PR
    ci.py reviewed <upstream>               exit 0 only while the owner's review of that upstream commit is a success
    ci.py pin-tag <tag> <commit>            fetch upstream main and tag; fail unless the tag still peels to commit
    ci.py replay <tree> <onto>              in <tree> (our main, upstream fetched), replay our commits onto <onto>
    ci.py regenerate <tree> <onto>          rewrite the generated files in <tree> (no commit)
    ci.py app-info <tag> <dir>              name, bundle id, version and build of upstream's release zip
    ci.py issue open <kind> <title> <cause> [<details.md>] | issue close <kind>
    ci.py design-notice <tree> <old upstream> <new upstream>
    ci.py hold <moved_at> [<now>]           PR list JSON on stdin: exit 0 while the rebase hold is on (kick.sh), else 1
    ci.py tested-key [<commit>]             tree of the commit without project, scheme, README: pr.yml names its artifact by it, plan looks main's up
    ci.py tested-run [<commit>]             URL of the green PR build of that tree, or nothing: land.sh skips its harness pass on it

Our commits are merge-base(main, upstream main)..main. Replaying cherry-picks them in order without the GENERATED
files, so those never conflict and never travel in our diffs. Two commits are made afresh instead of picked:
"Notchcast: remove upstream workflows" (git rm -r .github/workflows), so upstream workflow edits never conflict and
new ones never land, and "Notchcast: generated files", always last, which rewrites GENERATED (`regenerate`).
Catalog conflicts merge by key; other conflicts use per-file diffs from the replay tip in main's
replay-fixes/<lowercase subject, non-alphanumerics hyphenated>[.<base label>].patch (the first that applies) or fail.
A commit with patches of the same name in replay-adaptations/ gets the first that applies after its pick, however
the pick went; when none applies the replay fails on that commit.
Failures are remembered as refs/notchcast-failed/<main|release-<tag>>-<upstream or tag>-<our main>, so the same
input is retried only when upstream or our main changes, and reported as one open issue per kind (label
notchcast-<kind>: sync = replay onto new upstream, main = main tested as it is, release), which a newer failure with
the same cause only retitles; notchcast/update.sh reports each issue and cause once through its notify hook.
main moves onto upstream U only once the repo owner set a success REVIEW_CONTEXT status on U (upstream_review);
until then `stage` keeps U's diff on REVIEW_HEAD in one draft PR labelled REVIEW_LABEL. A release is signed only
when its tagged commit is main's upstream base or carries such a status itself; a mere ancestor of U never counts."""
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REMOVE_WORKFLOWS = "Notchcast: remove upstream workflows"
GENERATED_COMMIT = "Notchcast: generated files"
PBXPROJ = "Tinycast.xcodeproj/project.pbxproj"
RUNTIME_JS = "Tinycast/Resources/RaycastRuntime.generated.js"
# Rewritten by `regenerate`, never taken from our commits.
SCHEME = "Tinycast.xcodeproj/xcshareddata/xcschemes/Tinycast.xcscheme"
GENERATED = [PBXPROJ, SCHEME, RUNTIME_JS, "README.md"]
# Never pruned (notchcast/prune-paths.txt); docs/*.md is kept too.
KEEP = ["LICENSE", "NOTICE.md", "AGENTS.md", "Tests", "Scripts/raycast-runtime"]
# Upstream changes here mean notchcast/docs/design-system.md may need a refresh.
DESIGN_PATHS = ["Tinycast/DesignSystem/", ":(glob)**/Theme.swift", "docs/ui.md"]
BOT = {
    "GIT_COMMITTER_NAME": "github-actions[bot]",
    "GIT_COMMITTER_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com",
}
# Hand changes for a commit that picks without conflict yet breaks on the new upstream.
ADAPTATIONS = "notchcast/replay-adaptations"
# The review PR's branches: upstream's diff without .github/workflows, so no push or PR event runs a workflow.
REVIEW_BASE, REVIEW_HEAD = "sync/upstream-base", "sync/upstream"
TAG_RE = re.compile(r"v(\d+)\.(\d+)\.(\d+)(?:-[a-z]+\.(\d+))?")


def config():
    values = {}
    for line in (HERE / "config.env").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key] = value.strip().strip('"')
    return values


AUTHOR = "{MAINTAINER_NAME} <{MAINTAINER_EMAIL}>".format(**config())


def run(*cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=dict(os.environ, **(env or {})), text=True,
                          check=True, capture_output=True).stdout.strip()


def ls_remote(url, *patterns):
    refs = {}
    for line in run("git", "ls-remote", url, *patterns).splitlines():
        sha, ref = line.split("\t")
        refs[ref] = sha
    return refs


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


def release_tags(repo):
    pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"))
    return {r["tag_name"] for page in pages for r in page}


def rebase_hold(prs, moved_at, now):
    numbers = sorted(pr["number"] for pr in prs if not pr["isDraft"] and not pr["isCrossRepository"])
    if not numbers:
        return False, ""
    names = ", ".join(f"#{number}" for number in numbers)
    left = 12 - (now - moved_at) / 3600
    if left > 0:
        return True, f"open PRs {names}; {left:.1f} h of 12 left"
    return False, f"::warning::main: 12-hour hold expired with PRs {names} still open"


def hold(moved_at, now=None):
    held, message = rebase_hold(json.load(sys.stdin), int(moved_at), int(now) if now else time.time())
    print(message)
    sys.exit(0 if held else 1)


def tested_key(commit="HEAD", cwd=None):
    """Tree of commit without the project, scheme and README: CI regenerates or never tests those. The runtime stays in:
    CI never rebuilds it and harnesses load it."""
    with tempfile.TemporaryDirectory() as scratch:
        env = {"GIT_INDEX_FILE": f"{scratch}/index"}
        run("git", "read-tree", commit, cwd=cwd, env=env)
        run("git", "update-index", "--force-remove", "--", PBXPROJ, SCHEME, "README.md", cwd=cwd, env=env)
        return run("git", "write-tree", cwd=cwd, env=env)


def tested_run(artifacts, fetch_run, fork_repo):
    """The run of the first live `tested-tree-<key>` artifact that is a green PR run of our own repo, else None."""
    for artifact in artifacts:
        if artifact.get("expired"):
            continue
        found = fetch_run(artifact["workflow_run"]["id"])
        head = (found.get("head_repository") or {}).get("full_name") or ""
        if (found.get("name") == "PR" and found.get("path") == ".github/workflows/pr.yml"
                and found.get("conclusion") == "success" and head.lower() == fork_repo.lower()):
            return found
    return None


def tested_build(commit, repo):
    """The green PR run of our repo that built and tested commit's tree (tested_key), else None."""
    key = tested_key(commit)
    listing = json.loads(run("gh", "api", f"repos/{repo}/actions/artifacts?name=tested-tree-{key}&per_page=100"))
    return tested_run(listing["artifacts"], lambda id: json.loads(run("gh", "api", f"repos/{repo}/actions/runs/{id}")), repo)


def tested_build_url(commit="HEAD"):
    """land.sh: print the URL of the green PR build of commit's tree, or nothing. Any error means no build."""
    try:
        found = tested_build(commit, config()["FORK_REPO"])
    except (subprocess.CalledProcessError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"tested-run lookup skipped: {error}", file=sys.stderr)
        return
    if found:
        print(found["html_url"])


def reuse_pr_build(main, cfg):
    """A green PR build of main's tree already built and tested it: mark main tested and return that run, else None.
    Any error means no reuse, so main is tested as before."""
    repo = cfg["FORK_REPO"]
    try:
        found = tested_build(main, repo)
        if found is None:
            print(f"main: no green PR build of tree {tested_key(main)[:10]}")
            return None
        run("gh", "api", "-X", "POST", f"repos/{repo}/statuses/{main}", "-f", "state=success", "-f",
            f"context={cfg['TESTED_CONTEXT']}", "-f", "description=Tree built and tested green by a PR build",
            "-f", f"target_url={found['html_url']}")
    except (subprocess.CalledProcessError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"::notice::PR build reuse skipped: {error}")
        return None
    # The main job, whose step closes it, does not run on reuse.
    try:
        issue_close("main")
    except (subprocess.CalledProcessError, ValueError, KeyError, TypeError) as error:
        print(f"::notice::notchcast-main issue not closed: {error}")
    return found


def upstream_review(sha, cfg):
    """State of the repo owner's newest REVIEW_CONTEXT status on upstream sha in our repo, or None. Statuses by any
    other account, the Actions bot included, never count, so no workflow token can pass the gate."""
    repo = cfg["FORK_REPO"]
    owner = repo.split("/")[0].lower()
    try:
        pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/commits/{sha}/statuses?per_page=100"))
    except (subprocess.CalledProcessError, ValueError) as error:
        print(f"review record of {sha[:10]} not readable ({error}); counted as none")
        return None
    for status in (status for page in pages for status in page):
        if status.get("context") == cfg["REVIEW_CONTEXT"] and ((status.get("creator") or {}).get("login") or "").lower() == owner:
            return status.get("state")
    return None


def reviewed(sha):
    """Exit 0 only while the owner's review of upstream sha is a success: the main push re-reads plan's verdict."""
    state = upstream_review(sha, config())
    print(f"review of upstream {sha[:10]}: {state or 'none'}")
    sys.exit(0 if state == "success" else 1)


def pin_tag(tag, commit):
    """Fetch upstream main and tag into this checkout; fail unless the tag still peels to commit, as plan saw it."""
    run("git", "fetch", "-q", f"https://github.com/{config()['UPSTREAM_REPO']}.git",
        "+refs/heads/main:refs/remotes/upstream/main", f"+refs/tags/{tag}:refs/tags/{tag}")
    now = run("git", "rev-parse", f"refs/tags/{tag}^{{commit}}")
    if now != commit:
        sys.exit(f"::error::upstream moved tag {tag} from {commit[:10]}, the commit plan cleared, to {now[:10]}")


def plan():
    """Run in a checkout of our main with history (fetch-depth 0)."""
    cfg = config()
    upstream = f"https://github.com/{cfg['UPSTREAM_REPO']}.git"
    main = run("git", "rev-parse", "HEAD")
    run("git", "fetch", "-q", upstream, "refs/heads/main")
    upstream_main = run("git", "rev-parse", "FETCH_HEAD")
    base = run("git", "merge-base", main, upstream_main)
    tag_refs = ls_remote(upstream, "refs/tags/*")
    upstream_tags = {r.removeprefix("refs/tags/") for r in tag_refs if not r.endswith("^{}")}
    failed = {r.removeprefix("refs/notchcast-failed/")
              for r in ls_remote(f"https://github.com/{cfg['FORK_REPO']}.git", "refs/notchcast-failed/*")}

    main_key = f"main-{upstream_main}-{main}"
    rebase = base != upstream_main
    # Read before any job runs upstream's tree.
    review = upstream_review(upstream_main, cfg) if rebase else None
    held = False
    if rebase:
        prs = json.loads(run("gh", "pr", "list", "-R", cfg["FORK_REPO"], "--base", "main", "--state", "open", "--limit", "1000",
                             "--json", "number,isDraft,isCrossRepository"))
        moved_at = int(run("git", "log", "--first-parent", "--reverse", "--format=%ct", f"{base}..{upstream_main}").splitlines()[0])
        held, message = rebase_hold(prs, moved_at, time.time())
        if message:
            print(f"main: hold rebase onto upstream {upstream_main[:10]}: {message}" if held else message)
    if not rebase:
        print(f"main: contains upstream {upstream_main[:10]}")
    elif review != "success":
        print(f"::notice::main stays on upstream {base[:10]}: upstream {upstream_main[:10]} has "
              f"{'no review record' if review is None else f'review {review}'}; see the {cfg['REVIEW_LABEL']} PR")
        rebase = False
    elif held:
        rebase = False
    elif main_key in failed:
        print(f"main: {main_key} already failed; waiting for upstream or main to change")
        rebase = False
    else:
        print(f"main: rebase {main[:10]} onto upstream {upstream_main[:10]}")
        # The replay alone, here on Linux, before a macOS runner is spent on it.
        run("git", "update-ref", "refs/remotes/upstream/main", upstream_main)
        with tempfile.TemporaryDirectory() as tree:
            run("git", "worktree", "add", "-q", "--detach", tree, main)
            try:
                replay(tree, upstream_main, check=True)
            except Conflict as conflict:
                rebase = False
                details = Path(tempfile.mkstemp(suffix=".md")[1])
                details.write_text(conflict.report(tree, base, upstream_main, cfg["UPSTREAM_REPO"]))
                issue_open("sync", f"Sync blocked: upstream {upstream_main[:7]} + main {main[:7]}", conflict.cause,
                           details)
                print(f"::warning::{conflict.cause} (see the notchcast-sync issue)")
            finally:
                run("git", "worktree", "remove", "--force", tree)

    ours = release_tags(cfg["FORK_REPO"])
    theirs = json.loads(run("gh", "release", "list", "-R", cfg["UPSTREAM_REPO"], "-L", "30",
                            "--json", "tagName,name,isDraft,isPrerelease"))
    baseline = version_key(cfg["BASELINE_TAG"])
    releases = []
    for r in sorted((r for r in theirs if version_key(r["tagName"])), key=lambda r: version_key(r["tagName"])):
        tag = r["tagName"]
        if r["isDraft"] or tag in ours or tag not in upstream_tags or version_key(tag) < baseline:
            continue
        if f"release-{tag}-{main}" in failed:
            print(f"release {tag}: already failed with this main; skipped")
            continue
        # Only a tree someone reviewed whole is signed: an ancestor of U is not, as U may delete what it added.
        tag_commit = tag_refs.get(f"refs/tags/{tag}^{{}}", tag_refs[f"refs/tags/{tag}"])
        if tag_commit != base and upstream_review(tag_commit, cfg) != "success":
            print(f"::notice::release {tag}: waits for a review of its own commit {tag_commit[:10]} "
                  f"({cfg['REVIEW_CONTEXT']} success on it), or for main to hold exactly that commit")
            continue
        print(f"release {tag}: mirror {tag_commit[:10]}")
        releases.append({"tag": tag, "commit": tag_commit, "title": r["name"], "prerelease": r["isPrerelease"]})

    statuses = json.loads(run("gh", "api", f"repos/{cfg['FORK_REPO']}/commits/{main}/status"))["statuses"]
    tested = any(s["context"] == cfg["TESTED_CONTEXT"] and s["state"] == "success" for s in statuses)
    # Without a rebase, a main commit is tested as it is, once: a red one waits for a new main.
    test_main = not rebase and not tested and f"test-{main}" not in failed
    reused = reuse_pr_build(main, cfg) if test_main else None
    if reused:
        print(f"main {main[:10]}: tested by PR build {reused['html_url']}")
        test_main = False
        tested = True
    print(f"main {main[:10]}: {'tested' if tested else 'failed before' if not test_main and not rebase else 'not tested yet'}")
    # open: upstream waits for review; close: main holds upstream, so an open review PR is done.
    stage = "open" if base != upstream_main and review != "success" else ""
    if base == upstream_main and json.loads(run("gh", "pr", "list", "-R", cfg["FORK_REPO"], "--label", cfg["REVIEW_LABEL"],
                                                  "--state", "open", "--json", "number")):
        stage = "close"
    output(rebase=str(rebase).lower(), test_main=str(test_main).lower(), main=main, base=base,
           upstream_main=upstream_main, main_key=main_key, releases=json.dumps(releases, separators=(",", ":")),
           stage=stage)


def without_workflows(commit, cwd=None):
    """Tree of commit without .github/workflows."""
    with tempfile.TemporaryDirectory() as scratch:
        env = {"GIT_INDEX_FILE": f"{scratch}/index"}
        run("git", "read-tree", commit, cwd=cwd, env=env)
        run("git", "rm", "-r", "-q", "-f", "--cached", "--ignore-unmatch", "--", ".github/workflows", cwd=cwd, env=env)
        return run("git", "write-tree", cwd=cwd, env=env)


def review_commits(base, upstream, cwd=None):
    """(review base, review head): base and upstream without workflows, the head's parents being the review base and
    upstream, so the PR diff is base..upstream and its commits are upstream's. Same inputs, same commits."""
    date = run("git", "show", "-s", "--format=%cI", upstream, cwd=cwd)
    name, email = AUTHOR.removesuffix(">").split(" <")
    env = dict(BOT, GIT_AUTHOR_NAME=name, GIT_AUTHOR_EMAIL=email, GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
    review_base = run("git", "commit-tree", without_workflows(base, cwd), "-p", base,
                      "-m", f"Notchcast: upstream review base {base[:10]}", cwd=cwd, env=env)
    head = run("git", "commit-tree", without_workflows(upstream, cwd), "-p", review_base, "-p", upstream,
               "-m", f"Notchcast: upstream {base[:10]}..{upstream[:10]} for review", cwd=cwd, env=env)
    return review_base, head


def fenced(text, limit):
    """text in a code block that no backtick in it can close, cut to limit characters."""
    text = text.replace("`", "'")
    if len(text) > limit:
        text = text[:limit].rsplit("\n", 1)[0] + "\n…"
    return f"```\n{text}\n```"


def review_body(base, upstream, cfg, cwd=None):
    up, fork, context = cfg["UPSTREAM_REPO"], cfg["FORK_REPO"], cfg["REVIEW_CONTEXT"]
    command = (f"gh api -X POST repos/{fork}/statuses/{upstream} -f context={context} -f state=success "
               f"-f description='PASS {base[:7]}..{upstream[:7]}'")
    commits = run("git", "log", "--format=%h %s", f"{base}..{upstream}", cwd=cwd)
    stat = run("git", "diff", "--stat=120", base, upstream, cwd=cwd)
    return f"""Upstream `{up}` moved from `{base}` (in our `main`) to `{upstream}`. Sync moves `main` onto it only after the keeper's review passes; until then nothing of it is built, run or released here.

Range: `{base}..{upstream}`, [compare on GitHub](https://github.com/{up}/compare/{base}...{upstream}). This PR's files are that diff without `.github/workflows` (so no workflow runs on it; the full range shows them), and it is never merged: Sync closes it once `main` holds `{upstream[:10]}`, and a newer upstream replaces its range.

Review: the keeper runs `gate pick notchcast review --from {REVIEW_HEAD}` (the gate) and `review-kimi` (a second voice) with `notchcast/review/upstream-review.md`, then records the verdict from their own `gh` login (a status from any other account, the Actions bot included, is ignored):

```
{command}
```

On FAIL, the same with `-f state=failure` and the reasons in `description`.

Commits:

{fenced(commits, 20000)}

Diff stat:

{fenced(stat, 30000)}
"""


def stage(action, base, upstream):
    """Run in a checkout of our main with history, the deploy key set up for `open`."""
    cfg = config()
    repo = cfg["FORK_REPO"]
    label = cfg["REVIEW_LABEL"]
    prs = json.loads(run("gh", "pr", "list", "-R", repo, "--label", label, "--state", "open", "--json", "number"))
    if action == "close":
        for pr in prs:
            run("gh", "pr", "close", str(pr["number"]), "-R", repo, "--comment", f"`main` holds upstream `{upstream[:10]}` now.")
        return
    run("git", "fetch", "-q", f"https://github.com/{cfg['UPSTREAM_REPO']}.git", upstream)
    review_base, head = review_commits(base, upstream)
    run("git", "-c", "core.hooksPath=/dev/null", "push", "-q", "--atomic", "--force", os.environ["FORK_SSH"],
        f"{review_base}:refs/heads/{REVIEW_BASE}", f"{head}:refs/heads/{REVIEW_HEAD}")
    title = f"Upstream review: {cfg['UPSTREAM_REPO']} {base[:7]}..{upstream[:7]}"
    with tempfile.NamedTemporaryFile("w", suffix=".md") as body:
        body.write(review_body(base, upstream, cfg))
        body.flush()
        run("gh", "label", "create", label, "-R", repo, "--color", "b60205", "--force")
        if prs:
            run("gh", "pr", "edit", str(prs[0]["number"]), "-R", repo, "--title", title, "--body-file", body.name)
            print(f"updated PR #{prs[0]['number']}: {title}")
        else:
            print(run("gh", "pr", "create", "-R", repo, "--draft", "--base", REVIEW_BASE, "--head", REVIEW_HEAD,
                      "--label", label, "--title", title, "--body-file", body.name))


class Conflict(Exception):
    def __init__(self, subject, files):
        super().__init__(f"{subject}: {' '.join(files)}")
        self.subject, self.files = subject, files
        # Stable across upstream commits, so a newer upstream stopping on the same thing only retitles the issue.
        self.cause = f"{subject}: {' '.join(files)}"

    def report(self, tree, base, upstream, upstream_repo):
        """The upstream commits since our base that touched the conflicting files: usually the one to look at."""
        url = f"https://github.com/{upstream_repo}/commit"
        touched = run("git", "log", f"--format=- [`%h`]({url}/%H) %s", f"{base}..{upstream}", "--", *self.files,
                      cwd=tree)
        files = ", ".join(f"`{f}`" for f in self.files)
        return (f"**{self.subject}** no longer applies to upstream [`{upstream[:7]}`]({url}/{upstream}): {files}.\n\n"
                + (f"Upstream commits since [`{base[:7]}`]({url}/{base}) that touch them:\n\n{touched}\n\n"
                   "If one of them ships what our commit does, drop our commit; otherwise redo it on top.\n"
                   if touched else "No upstream commit touched them, so an earlier commit of ours moved the lines.\n"))


def replay_fixes(tree, main, name, folder="notchcast/replay-fixes"):
    """main's stored patches for one commit: <name>.patch, then <name>.<base label>.patch for older release bases."""
    listed = run("git", "ls-tree", "--name-only", main, f"{folder}/", cwd=tree).splitlines()
    bare = f"{folder}/{name}.patch"
    return ([bare] if bare in listed else []) + sorted(
        path for path in listed
        if path.startswith(bare.removesuffix("patch")) and path.endswith(".patch") and path != bare)


def replay(tree, onto, check=False):
    """Replay merge-base(HEAD, upstream main)..HEAD onto `onto` in tree; leaves tree detached at the result.
    With check=True (plan, on Linux) the generated files are not regenerated. Raises Conflict."""
    main = run("git", "rev-parse", "HEAD", cwd=tree)
    upstream_main = run("git", "rev-parse", "refs/remotes/upstream/main", cwd=tree)
    base = run("git", "merge-base", main, upstream_main, cwd=tree)
    commits = run("git", "rev-list", "--reverse", "--topo-order", f"{base}..{main}", cwd=tree).split()
    merges = run("git", "rev-list", "--merges", f"{base}..{main}", cwd=tree)
    if merges:
        sys.exit(f"main has merge commits ({merges.split()[0][:10]}…); keep main linear")
    run("git", "checkout", "-q", "--detach", onto, cwd=tree)
    generated_commit = None
    for sha in commits:
        subject = run("git", "show", "-s", "--format=%s", sha, cwd=tree)
        print(f"replay {sha[:10]} {subject}", flush=True)
        name = re.sub(r"[^a-z0-9]+", "-", subject.lower()).strip("-")
        if subject == GENERATED_COMMIT:
            generated_commit = sha
            continue
        if subject == REMOVE_WORKFLOWS:
            run("git", "rm", "-r", "-q", "--ignore-unmatch", ".github/workflows", cwd=tree)
        else:
            picked = subprocess.run(["git", "cherry-pick", "--no-commit", sha], cwd=tree, text=True,
                                    capture_output=True)
            conflicts = run("git", "diff", "--name-only", "--diff-filter=U", cwd=tree).split()
            catalog = "Tinycast/Resources/Localizable.xcstrings"
            resolved_catalog = False
            catalog_refs = (sha + "^", "HEAD", sha)
            if catalog in conflicts and all(
                    subprocess.run(["git", "cat-file", "-e", f"{ref}:{catalog}"], cwd=tree,
                                   stderr=subprocess.DEVNULL).returncode == 0 for ref in catalog_refs):
                with tempfile.TemporaryDirectory() as directory:
                    inputs = []
                    for index, ref in enumerate(catalog_refs):
                        path = Path(directory) / str(index)
                        path.write_text(run("git", "show", f"{ref}:{catalog}", cwd=tree) + "\n")
                        inputs.append(str(path))
                    merged = subprocess.run(
                        [sys.executable, str(HERE / "xcstrings-union.py"), *inputs,
                         str(Path(tree).resolve() / catalog)], text=True, capture_output=True)
                if merged.returncode == 0:
                    run("git", "add", "--", catalog, cwd=tree)
                    conflicts.remove(catalog)
                    resolved_catalog = True
            if (picked.returncode and not conflicts and not resolved_catalog
                    or set(conflicts) - set(GENERATED)):
                applied = None
                expected = set(conflicts) - set(GENERATED) - {catalog}
                for fix in replay_fixes(tree, main, name):
                    patch = subprocess.run(["git", "show", f"{main}:{fix}"], cwd=tree, text=True,
                                           capture_output=True, check=True).stdout
                    paths = subprocess.run(["git", "apply", "--numstat", "-z", "-"], input=patch,
                                           cwd=tree, text=True, capture_output=True)
                    covered = {entry.split("\t", 2)[2] for entry in paths.stdout.split("\0") if entry}
                    if not expected or paths.returncode or covered != expected:
                        continue
                    for path in expected:
                        if subprocess.run(["git", "cat-file", "-e", f"HEAD:{path}"], cwd=tree,
                                          stderr=subprocess.DEVNULL).returncode == 0:
                            run("git", "checkout", "HEAD", "--", path, cwd=tree)
                        else:
                            run("git", "rm", "-q", "-f", "--ignore-unmatch", "--", path, cwd=tree)
                    # git apply is all-or-nothing, so a fix for another base leaves the tree for the next one.
                    applied = subprocess.run(["git", "apply", "--index", "-"], input=patch,
                                             cwd=tree, text=True, capture_output=True)
                    if applied.returncode == 0:
                        break
                remaining = run("git", "diff", "--name-only", "--diff-filter=U", cwd=tree).split()
                if applied is None or applied.returncode or set(remaining) - set(GENERATED):
                    run("git", "reset", "-q", "--hard", cwd=tree)
                    raise Conflict(subject, [f for f in conflicts if f not in GENERATED]
                                   or [(picked.stderr.strip().splitlines() or ["cherry-pick failed"])[0]])
            adaptations = replay_fixes(tree, main, name, ADAPTATIONS)
            for adaptation in adaptations:
                patch = subprocess.run(["git", "show", f"{main}:{adaptation}"], cwd=tree, text=True,
                                       capture_output=True, check=True).stdout
                if subprocess.run(["git", "apply", "--index", "-"], input=patch, cwd=tree, text=True,
                                  capture_output=True).returncode == 0:
                    break
            else:
                if adaptations:
                    patch = subprocess.run(["git", "show", f"{main}:{adaptations[0]}"], cwd=tree, text=True,
                                           capture_output=True, check=True).stdout
                    paths = subprocess.run(["git", "apply", "--numstat", "-z", "-"], input=patch, cwd=tree,
                                           text=True, capture_output=True).stdout
                    run("git", "reset", "-q", "--hard", cwd=tree)
                    raise Conflict(subject, [entry.split("\t", 2)[2] for entry in paths.split("\0") if entry]
                                   or [f"{adaptations[0]} does not apply"])
            # Generated files stay as they were; the generated-files commit rewrites them.
            for path in GENERATED:
                if subprocess.run(["git", "cat-file", "-e", f"HEAD:{path}"], cwd=tree, stderr=subprocess.DEVNULL).returncode == 0:
                    run("git", "checkout", "HEAD", "--", path, cwd=tree)
                else:
                    run("git", "rm", "-q", "-f", "--ignore-unmatch", "--", path, cwd=tree)
        run("git", "commit", "-q", "--no-verify", "--allow-empty", "-C", sha, "--author", AUTHOR, cwd=tree, env=BOT)
    if not check:
        regenerate(tree, onto)
        run("git", "add", "-A", "--", *GENERATED, cwd=tree)
        message = ["-C", generated_commit] if generated_commit else ["-m", GENERATED_COMMIT]
        run("git", "commit", "-q", "--no-verify", "--allow-empty", *message, "--author", AUTHOR, cwd=tree, env=BOT)
    print(run("git", "log", "--format=%h %an | %cn | %s", f"{onto}..HEAD", cwd=tree))


def pruned(tree):
    """Paths in notchcast/prune-paths.txt. None may cover a kept path (license notices, agent and feature docs,
    harnesses, the extension runtime sources)."""
    prune = Path(tree) / "notchcast/prune-paths.txt"
    paths = [line.strip() for line in prune.read_text().splitlines()] if prune.exists() else []
    paths = [path for path in paths if path and not path.startswith("#")]
    for path in paths:
        bare = path.rstrip("/")
        if any(keep == bare or keep.startswith(bare + "/") or bare.startswith(keep + "/") for keep in KEEP) \
                or bare in ("", ".", "docs") or bare.startswith("docs/") and (
                    bare.endswith(".md") or path.endswith("/") or (Path(tree) / bare).is_dir()):
            sys.exit(f"notchcast/prune-paths.txt: {path} covers a path Notchcast keeps")
    return paths


def regenerate(tree, onto):
    """Write GENERATED in tree: notchcast/README.public.md as README.md, the Xcode project from project.yml ($XCODEGEN), and the
    extension runtime bundle when our commits change its sources. Also stage the removal of every path in
    notchcast/prune-paths.txt (upstream files the app does not need), so the removal rides in the generated-files
    commit, which a replay never picks and so never conflicts."""
    tree = Path(tree)
    paths = pruned(tree)
    if paths:
        run("git", "rm", "-r", "-q", "--ignore-unmatch", "--", *paths, cwd=tree)
    (tree / "README.md").write_text((tree / "notchcast/README.public.md").read_text())
    if os.environ.get("XCODEGEN"):
        run(os.environ["XCODEGEN"], "generate", "--quiet", cwd=tree)
    elif subprocess.run(["git", "diff", "--quiet", onto, "HEAD", "--", "project.yml"], cwd=tree).returncode:
        sys.exit("our commits change project.yml; set XCODEGEN to regenerate the project")
    runtime = tree / "Scripts/raycast-runtime"
    if subprocess.run(["git", "diff", "--quiet", onto, "HEAD", "--", str(runtime)], cwd=tree).returncode:
        run("npm", "ci", "--no-audit", "--no-fund", cwd=runtime)
        run("node", "build.mjs", cwd=runtime)


def issue_open(kind, title, cause, details=None):
    """One open issue per kind. The same cause on a newer input only retitles it, so it notifies once."""
    repo, label = os.environ["GITHUB_REPOSITORY"], f"notchcast-{kind}"
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{repo}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    marker = f"<!-- cause: {cause} -->"
    body = (f"{title}: see [the run]({run_url}). Nothing was pushed or published; it is retried when upstream or "
            f"`main` changes.\n\n" + (Path(details).read_text() + "\n" if details else "") + marker)
    run("gh", "label", "create", label, "-R", repo, "--color", "d93f0b", "--force")
    found = json.loads(run("gh", "issue", "list", "-R", repo, "--label", label, "--state", "open",
                           "--json", "number,title,body"))
    if not found:
        print(run("gh", "issue", "create", "-R", repo, "--label", label, "--title", title, "--body", body))
    elif marker in found[0]["body"]:
        if found[0]["title"] != title:
            run("gh", "issue", "edit", str(found[0]["number"]), "-R", repo, "--title", title)
    else:
        run("gh", "issue", "edit", str(found[0]["number"]), "-R", repo, "--title", title, "--body", body)
        run("gh", "issue", "comment", str(found[0]["number"]), "-R", repo, "--body", body)


def issue_close(kind, cause=None):
    """Close the open issue of kind; with a cause, only if it is that cause's."""
    repo = os.environ["GITHUB_REPOSITORY"]
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{repo}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    for found in json.loads(run("gh", "issue", "list", "-R", repo, "--label", f"notchcast-{kind}", "--state", "open",
                                "--json", "number,body")):
        if cause is None or f"<!-- cause: {cause} -->" in found["body"]:
            run("gh", "issue", "close", str(found["number"]), "-R", repo, "--comment",
                f"Went through in [this run]({run_url}).")


def issue(action, kind, *args):
    issue_open(kind, *args) if action == "open" else issue_close(kind, *args)


def design_notice(tree, old, new):
    """One notchcast-design issue per sync that brings upstream design-system changes; it stays open as the to-do."""
    cfg = config()
    url = f"https://github.com/{cfg['UPSTREAM_REPO']}/commit"
    commits = run("git", "log", f"--format=- [`%h`]({url}/%H) %s", f"{old}..{new}", "--", *DESIGN_PATHS, cwd=tree)
    if not commits:
        return
    repo = os.environ["GITHUB_REPOSITORY"]
    run("gh", "label", "create", "notchcast-design", "-R", repo, "--color", "1d76db", "--force")
    print(run("gh", "issue", "create", "-R", repo, "--label", "notchcast-design",
              "--title", f"Refresh notchcast/docs/design-system.md (upstream {new[:7]})",
              "--body", f"Upstream commits from `{old[:7]}` to `{new[:7]}` that touch the design system:\n\n{commits}\n"))


def app_info(tag, out_dir):
    """Name, bundle id, version and build from upstream's own thin zip, so our build matches it."""
    cfg = config()
    with tempfile.TemporaryDirectory() as tmp:
        run("gh", "release", "download", tag, "-R", cfg["UPSTREAM_REPO"], "-D", tmp, "-p", "Tinycast-[0-9]*.zip")
        # -Handoff.zip is upstream's bundle-id bridge for its own in-app updater (v0.12.15), not the app.
        zips = [z for z in Path(tmp).glob("Tinycast-*.zip")
                if "-Universal-" not in z.name and not z.name.endswith("-Handoff.zip")]
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
    {"plan": plan, "replay": replay, "regenerate": regenerate, "app-info": app_info, "issue": issue,
     "design-notice": design_notice, "tested-key": lambda *a: print(tested_key(*a)),
     "tested-run": tested_build_url, "hold": hold, "stage": stage, "reviewed": reviewed, "pin-tag": pin_tag}[command](*args)
