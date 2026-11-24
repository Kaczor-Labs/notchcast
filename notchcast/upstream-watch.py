#!/usr/bin/env python3
"""Keep one open `upstream-watch` issue per feature listing new commits of the projects we borrow from.

    upstream-watch.py             file or update the issues (needs GH_TOKEN and GITHUB_REPOSITORY)
    upstream-watch.py --dry-run   print what it would file; writes nothing

Sources and their path map are in notchcast/upstreams.json; see notchcast/README.md, "Upstream watch".
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
LABEL = "upstream-watch"
IDLE_WARN_DAYS = 50
LINE_MARKER = re.compile(r"<!-- upstream: (\S+) ([0-9a-f]{40}) -->")
BODY_LIMIT = 60000


LOG_FORMAT = "--format=%x1e%H%x1f%s"
LOG_HEADER = re.compile(r"\x1e([0-9a-f]{40})\x1f(.*)", re.S)


def run(*cmd, cwd=None):
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        sys.exit(f"{' '.join(cmd[:3])} failed: {result.stderr.strip()}")
    return result.stdout


def expand_braces(path):
    match = re.search(r"\{([^{}]*)\}", path)
    if not match:
        return [path]
    return [p for part in match[1].split(",")
            for p in expand_braces(path[:match.start()] + part + path[match.end():])]


def borrowed_paths(lines, repo):
    """(upstream path, feature) for each source file of `repo` named in a borrowing register line."""
    pairs = []
    for line in lines:
        feature, sep, rest = line.partition(":")
        if not sep or "←" not in rest:
            continue
        for raw in re.findall(re.escape(repo) + r"@[0-9a-f]+/([^\s:]+)", rest.split("←", 1)[1]):
            pairs += [(path, feature.strip()) for path in expand_braces(raw.rstrip(","))]
    return pairs


def build_map(paths, borrowed):
    """Ordered [(upstream path, [features])]: the data file's entries, then each borrowed file not yet covered."""
    entries = {path.rstrip("/"): list(features) for path, features in paths.items()}
    for path, feature in borrowed:
        features = entries.setdefault(path, [])
        if feature not in features:
            features.append(feature)
    return list(entries.items())


def parse_log(text):
    """[(sha, subject, [files])], oldest first, from `git log -z --name-only` with LOG_FORMAT."""
    commits = []
    for token in text.split("\0"):
        header = LOG_HEADER.fullmatch(token)
        if header:
            commits.append((header[1], header[2], []))
        elif token and commits:
            # -z still puts one newline before a commit's first file name; names come unquoted.
            files = commits[-1][2]
            files.append(token[1:] if not files and token.startswith("\n") else token)
    return commits[::-1]


def features_of(files, fmap):
    """(primary feature, [other features]) by mapped file count, ties by map order; None when nothing maps."""
    order = []
    for _, features in fmap:
        order += [f for f in features if f not in order]
    counts = {}
    for file in files:
        hit = set()
        for path, features in fmap:
            if file == path or file.startswith(path + "/"):
                hit.update(features)
        for feature in hit:
            counts[feature] = counts.get(feature, 0) + 1
    if not counts:
        return None
    ranked = sorted(counts, key=lambda f: (-counts[f], order.index(f)))
    return ranked[0], ranked[1:]


def clean_subject(subject):
    """Upstream text as inline code: no tag, marker or code span can be forged and no @name pings anyone."""
    text = re.sub(r"[<>`]", "", subject).strip()[:100]
    return f"`{text}`" if text else "`(no subject)`"


def feature_marker(repo, feature):
    return f"<!-- upstream-watch: {repo} {feature} -->"


def commit_line(repo, sha, subject, others):
    also = f" (also touches {', '.join(others)})" if others else ""
    return (f"- [ ] [`{sha[:8]}`](https://github.com/{repo}/commit/{sha}) {clean_subject(subject)}{also} "
            f"<!-- upstream: {repo} {sha} -->")


def issue_title(name, feature, count):
    return f"Look at {name} changes for {feature} ({count})"


def plan_actions(source, commits, fmap, issues):
    """The issue writes for one source: {"op": "create"|"edit", "number"?, "title", "body"}.

    A feature's new lines fill its newest open issue up to BODY_LIMIT, then as many new issues as they need.
    """
    repo, name = source["repo"], source["name"]
    seen = {m[2] for issue in issues for m in LINE_MARKER.finditer(issue["body"] or "") if m[1] == repo}
    grouped = {}
    for sha, subject, files in commits:
        mapped = features_of(files, fmap)
        if sha in seen or not mapped:
            continue
        seen.add(sha)
        grouped.setdefault(mapped[0], []).append(commit_line(repo, sha, subject, mapped[1]))
    actions = []
    for feature, lines in grouped.items():
        marker = feature_marker(repo, feature)
        open_ = [i for i in issues if i["state"].upper() == "OPEN" and marker in (i["body"] or "")]
        found = max(open_, key=lambda i: i["number"], default=None)
        header = (f"Commits in [{name}](https://github.com/{repo}) that touch files mapped to our **{feature}** "
                  f"in `notchcast/upstreams.json` or the borrowing register. Each link is the diff. Tick a line "
                  f"once looked at and close the issue when done; later commits then open a new one. "
                  f"Nothing is merged automatically.\n{marker}\n\n")
        body = found["body"].rstrip("\n") + "\n" if found else header
        while lines:
            taken = 0
            while taken < len(lines) and len(body) + len(lines[taken]) + 1 <= BODY_LIMIT:
                body += lines[taken] + "\n"
                taken += 1
            if taken:
                count = len([m for m in LINE_MARKER.finditer(body) if m[1] == repo])
                write = {"op": "edit", "number": found["number"]} if found else {"op": "create"}
                actions.append({**write, "title": issue_title(name, feature, count), "body": body})
            elif not found:
                sys.exit(f"a {feature} line does not fit in an issue body")
            lines, found, body = lines[taken:], None, header
    return actions


def idle_days(last_commit, now):
    """Whole days since `main`'s last commit, or None while under the warning line."""
    days = int((now - last_commit) // 86400)
    return days if days >= IDLE_WARN_DAYS else None


def fetch_commits(source, tmp):
    url = f"https://github.com/{source['repo']}.git"
    run("git", "init", "-q", tmp)
    run("git", "-C", tmp, "fetch", "-q", "--no-tags", "--filter=blob:none", url, source["branch"])
    since = source["since"]
    if subprocess.run(["git", "-C", tmp, "merge-base", "--is-ancestor", since, "FETCH_HEAD"],
                      capture_output=True).returncode:
        sys.exit(f"{source['repo']}: `since` {since} is not on {source['branch']}; move it in notchcast/upstreams.json")
    return parse_log(run("git", "-C", tmp, "log", "-z", "--no-merges", "--no-renames", LOG_FORMAT, "--name-only",
                         f"{since}..FETCH_HEAD"))


def list_issues(repo):
    """Every issue with LABEL, open and closed, read whole from the REST issues endpoint, not search."""
    lines = run("gh", "api", "--paginate", f"repos/{repo}/issues?labels={LABEL}&state=all&per_page=100",
                "--jq", ".[] | select(.pull_request | not) | {number, state, title, body}")
    return [json.loads(line) for line in lines.splitlines() if line.strip()]


def apply(actions, repo, dry_run, runner=subprocess.run):
    """Make each write; a rejected one is reported and the rest still go, then the run fails."""
    failed = 0
    for action in actions:
        if dry_run:
            where = f"edit #{action['number']}" if action["op"] == "edit" else "create"
            print(f"\n=== {where}: {action['title']}\n{action['body']}")
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".md") as body:
            body.write(action["body"])
            body.flush()
            if action["op"] == "edit":
                cmd = ["gh", "issue", "edit", str(action["number"]), "-R", repo]
            else:
                cmd = ["gh", "issue", "create", "-R", repo, "--label", LABEL]
            result = runner([*cmd, "--title", action["title"], "--body-file", body.name],
                            text=True, capture_output=True)
        print(result.stdout.strip() or f"{action['title']}: {result.stderr.strip()}")
        failed += bool(result.returncode)
    if failed:
        sys.exit(f"{failed} of {len(actions)} issue writes failed; the next run retries them")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="print the issue writes instead of making them")
    args = parser.parse_args()
    repo = os.environ.get("GITHUB_REPOSITORY") or sys.exit("set GITHUB_REPOSITORY to the owner/name issues go to")
    sources = json.loads((ROOT / "upstreams.json").read_text())["sources"]
    register = [line for f in sorted((ROOT / "licenses" / "borrowed").glob("*.txt"))
                for line in f.read_text().splitlines()]
    if not args.dry_run:
        run("gh", "label", "create", LABEL, "-R", repo, "--color", "5319e7", "--force")
    issues = list_issues(repo)
    actions = []
    for source in sources:
        with tempfile.TemporaryDirectory() as tmp:
            commits = fetch_commits(source, tmp)
        fmap = build_map(source["paths"], borrowed_paths(register, source["repo"]))
        planned = plan_actions(source, commits, fmap, issues)
        print(f"{source['repo']}: {len(commits)} commits since {source['since'][:8]}, {len(planned)} issue writes")
        actions += planned
    days = idle_days(int(run("git", "-C", str(ROOT), "log", "-1", "--format=%ct", "HEAD")), time.time())
    idle = "<!-- upstream-watch: idle -->"
    if days and not any(i["state"].upper() == "OPEN" and idle in (i["body"] or "") for i in issues):
        actions.append({"op": "create", "title": f"Scheduled workflows stop soon: no commit on main for {days} days",
                        "body": "GitHub disables a public repository's scheduled workflows after 60 days without "
                                "activity. Push a commit to `main`, or re-enable each workflow under Actions once "
                                f"it is off.\n{idle}\n"})
    apply(actions, repo, args.dry_run)

if __name__ == "__main__":
    main()
