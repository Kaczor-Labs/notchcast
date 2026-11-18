#!/usr/bin/env python3
"""Which macOS lanes a diff needs: pr.yml's route job and main-harnesses.yml's plan read it.

    lanes.py <base> <head>      prints build=true|false and scripts=true|false, one per line

build is the Xcode lane (pr.yml's checks and harness shards), scripts the script tests. Docs need neither. A notchcast/
file the build never reaches needs only the script tests. Every other path, unknown ones included, needs both, and so
does any error: a wrong answer may only ever run too much.
"""
import re
import subprocess
import sys

# What pr.yml's checks and harnesses jobs run from notchcast/; the build's closure grows from these.
BUILD_SEEDS = {"notchcast/ci-build.sh", "notchcast/actions/xcode/action.yml", "notchcast/actions/xcodegen/action.yml",
               "notchcast/actions/tests/action.yml", "notchcast/actions/route/action.yml", "notchcast/lanes.py"}
# Markdown under these is code: bundled, read by a check (check-addons, check-config) or fork-owned GitHub config.
NOT_DOCS = ("Tinycast/", "Tests/", ".github/", "notchcast/licenses/", "notchcast/vendor/", "NOTICE.md")
TOKEN = r"notchcast/[A-Za-z0-9_./-]+"


def git(*args):
    return subprocess.check_output(["git", *args], text=True, errors="replace")


def is_doc(path):
    return (path.startswith("docs/") or path.endswith(".md")) and not path.startswith(NOT_DOCS)


def build_closure(head, changed):
    """notchcast/ paths the build runs or reads: named by a path outside notchcast/, or by one already in, at head."""
    candidates = {path for path in set(git("ls-tree", "-r", "--name-only", head, "--", "notchcast").split("\n")) | changed
                  if path.startswith("notchcast/") and not is_doc(path)}
    named = [(path, re.compile(rf"(?<![\w.-]){re.escape(path.rsplit('/', 1)[1])}(?![\w-])")) for path in candidates]
    imported = [(path, re.compile(rf"\b(?:import|from)\s+{re.escape(path.rsplit('/', 1)[1][:-3])}\b"))
                for path in candidates if path.endswith(".py")]

    def refs(text):
        found = {path for path, pattern in named + imported if pattern.search(text)}
        for token in set(re.findall(TOKEN, text)):
            token = token.rstrip("/.")
            found |= {path for path in candidates if path == token or path.startswith(token + "/")}
        return found

    # Exit 1 is no match; .github is left out because only the seeds are what pr.yml's Xcode jobs run.
    outside = subprocess.run(["git", "grep", "-hoIE", TOKEN, head, "--", ".", ":!notchcast", ":!.github", ":!*.md"],
                             capture_output=True, text=True, errors="replace")
    if outside.returncode > 1:
        raise RuntimeError(outside.stderr)
    closure = BUILD_SEEDS | refs(outside.stdout)
    todo = list(closure)
    while todo:
        shown = subprocess.run(["git", "show", f"{head}:{todo.pop()}"], capture_output=True, text=True, errors="replace")
        new = refs(shown.stdout) - closure if shown.returncode == 0 else set()
        closure |= new
        todo += new
    return closure


def needs_build(path, closure):
    return not is_doc(path) and (not path.startswith("notchcast/") or path.startswith("notchcast/actions/")
                                 or path in closure)


def lanes(base, head):
    changed = set(git("diff", "--name-only", "--no-renames", "-z", base, head).split("\0")) - {""}
    closure = build_closure(head, changed)
    build = any(needs_build(path, closure) for path in changed)
    scripts = any(not is_doc(path) for path in changed)
    return build, scripts


def main():
    try:
        build, scripts = lanes(*sys.argv[1:3]) if len(sys.argv) == 3 and sys.argv[1] else (True, True)
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"lanes.py: {error}; running every lane", file=sys.stderr)
        build = scripts = True
    print(f"build={str(build).lower()}\nscripts={str(scripts).lower()}")


if __name__ == "__main__":
    main()
