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
ISSUE_LIMIT = 1000
IDLE_WARN_DAYS = 50
LINE_MARKER = re.compile(r"<!-- upstream: (\S+) ([0-9a-f]{40}) -->")
BODY_LIMIT = 60000


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
    """[(sha, subject, [files])], oldest first, from `git log --format=%x00%H%x1f%s --name-only`."""
    commits = []
    for record in text.split("\0")[1:]:
        head, _, files = record.partition("\n")
        sha, _, subject = head.partition("\x1f")
        commits.append((sha.strip(), subject, [f for f in files.splitlines() if f.strip()]))
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
    """The issue writes for one source: {"op": "create"|"edit", "number"?, "title", "body"}, one per feature."""
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
        body = found and found["body"].rstrip("\n") + "\n" + "\n".join(lines) + "\n"
        if found and len(body) <= BODY_LIMIT:
            count = len([m for m in LINE_MARKER.finditer(body) if m[1] == repo])
            actions.append({"op": "edit", "number": found["number"], "title": issue_title(name, feature, count),
                            "body": body})
        else:
            body = (f"Commits in [{name}](https://github.com/{repo}) that touch files mapped to our **{feature}** "
                    f"in `notchcast/upstreams.json` or the borrowing register. Each link is the diff. Tick a line "
                    f"once looked at and close the issue when done; later commits then open a new one. "
                    f"Nothing is merged automatically.\n{marker}\n\n" + "\n".join(lines) + "\n")
            actions.append({"op": "create", "title": issue_title(name, feature, len(lines)), "body": body})
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
    return parse_log(run("git", "-C", tmp, "log", "--no-merges", "--no-renames", "--format=%x00%H%x1f%s",
                         "--name-only", f"{since}..FETCH_HEAD"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="print the issue writes instead of making them")
    args = parser.parse_args()
    repo = os.environ.get("GITHUB_REPOSITORY") or "Kaczor-Labs/notchcast"
    sources = json.loads((ROOT / "upstreams.json").read_text())["sources"]
    register = [line for f in sorted((ROOT / "licenses" / "borrowed").glob("*.txt"))
                for line in f.read_text().splitlines()]
    if not args.dry_run:
        run("gh", "label", "create", LABEL, "-R", repo, "--color", "5319e7", "--force")
    issues = json.loads(run("gh", "issue", "list", "-R", repo, "--label", LABEL, "--state", "all",
                            "--limit", str(ISSUE_LIMIT), "--json", "number,state,title,body"))
    if len(issues) >= ISSUE_LIMIT:
        sys.exit(f"{len(issues)} {LABEL} issues reach the list limit; raise ISSUE_LIMIT before filing duplicates")
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
    for action in actions:
        if args.dry_run:
            where = f"edit #{action['number']}" if action["op"] == "edit" else "create"
            print(f"\n=== {where}: {action['title']}\n{action['body']}")
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".md") as body:
            body.write(action["body"])
            body.flush()
            if action["op"] == "edit":
                run("gh", "issue", "edit", str(action["number"]), "-R", repo, "--title", action["title"],
                    "--body-file", body.name)
            else:
                print(run("gh", "issue", "create", "-R", repo, "--label", LABEL, "--title", action["title"],
                          "--body-file", body.name).strip())


if __name__ == "__main__":
    main()
