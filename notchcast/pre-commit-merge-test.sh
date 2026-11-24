#!/bin/bash
# githooks/pre-commit on a fixture fork: a merge of main that brings newer upstream text is not charged for it,
# while a finding of our own is refused, mid-merge and in a normal commit, whichever base git could pick.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { echo "FAIL: $1"; cat "$scratch/output"; exit 1; }
export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
# One fixed date: git orders equal bases by date; only a tie leaves the pick to argument order.
export GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z'
mkdir -p "$scratch/bin" "$scratch/tools/githooks"
cp "$root/notchcast/githooks/pre-commit" "$scratch/tools/githooks/"
printf '#!/bin/sh\nexit 0\n' > "$scratch/tools/check-identity.sh"
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/gitleaks"
# Stands in for design-check.sh: a 'Title Case' line is a finding, and the base's count per file is the baseline.
cat > "$scratch/tools/design-check.sh" <<'STUB'
#!/bin/bash
set -eu
tree=$(git write-tree)
git grep -c 'Title Case' "$tree" -- Tinycast | while IFS=: read -r _ file ours; do
    theirs=$(git grep -c 'Title Case' "$1" -- "$file" | cut -d: -f3)
    [ "$ours" -le "${theirs:-0}" ] || { echo "error $file: Title Case"; exit 1; }
done
STUB
chmod +x "$scratch/bin/gitleaks" "$scratch/tools/"*.sh
# Last on PATH: an installed gitleaks runs, as in a real commit.
export PATH="$PATH:$scratch/bin"

git init --quiet -b upstream "$scratch/work"
cd "$scratch/work"
mkdir Tinycast
echo 'title: "Settings"' > Tinycast/Upstream.swift
git add Tinycast
git commit --quiet -m 'Upstream, old'
git switch --quiet -c main
echo 'title: "Fork"' > Tinycast/Fork.swift
git add Tinycast
git commit --quiet -m 'Fork'
git switch --quiet -c pr
echo 'title: "Cleaner"' > Tinycast/Cleaner.swift
git add Tinycast
git commit --quiet -m 'Cleaner'
git switch --quiet upstream
echo 'title: "Title Case"' >> Tinycast/Upstream.swift
git commit --quiet -am 'Upstream, new'
git update-ref refs/remotes/upstream/main upstream
git switch --quiet main
git merge --quiet -m 'Sync upstream' upstream
git switch --quiet pr
git config core.hooksPath "$scratch/tools/githooks"

git merge --quiet --no-commit main > "$scratch/output" 2>&1 || fail 'the fixture merge of main did not stage'
echo 'title: "Title Case"' >> Tinycast/Cleaner.swift
git add Tinycast
if git commit --quiet --no-edit > "$scratch/output" 2>&1; then
    fail 'a merge that stages our own finding was committed'
fi
grep -qx 'error Tinycast/Cleaner.swift: Title Case' "$scratch/output" || fail 'the refusal did not name our file'
echo 'PASS: a merge of main that also stages our own finding is refused'

git restore --quiet --source=HEAD --staged --worktree Tinycast/Cleaner.swift
git commit --quiet --no-edit > "$scratch/output" 2>&1 || fail 'a clean merge of main was refused'
git rev-parse --quiet --verify HEAD^2 > /dev/null || fail 'the merge commit was not made'
echo 'PASS: a clean merge of main that brings newer upstream text is committed'

git switch --quiet --detach HEAD^
echo 'title: "Title Case"' >> Tinycast/Upstream.swift
git add Tinycast
if git commit --quiet -m 'Ours' > "$scratch/output" 2>&1; then
    fail 'a normal commit was measured against upstream newer than its own base'
fi
grep -qx 'error Tinycast/Upstream.swift: Title Case' "$scratch/output" || fail 'the refusal did not name the file'
echo 'PASS: a normal commit is still measured against the upstream its branch has'

# Two equally good bases: a normal commit keeps git's pick for HEAD first, the base without the finding.
git init --quiet -b root "$scratch/bases"
cd "$scratch/bases"
mkdir Tinycast
echo 'title: "Settings"' > Tinycast/Upstream.swift
git add Tinycast
git commit --quiet -m 'Root'
git switch --quiet -c clean
echo 'title: "Fork"' > Tinycast/Fork.swift
git add Tinycast
git commit --quiet -m 'Clean'
git switch --quiet -c dirty root
echo 'title: "Title Case"' >> Tinycast/Upstream.swift
git commit --quiet -am 'Dirty'
git switch --quiet -c upstream
git merge --quiet --no-edit clean
git update-ref refs/remotes/upstream/main upstream
git switch --quiet -c pr clean
git merge --quiet --no-commit dirty > "$scratch/output" 2>&1 || fail 'the fixture merge of dirty did not stage'
git restore --quiet --source=clean --staged --worktree Tinycast/Upstream.swift
git commit --quiet --no-edit
[ "$(git merge-base HEAD refs/remotes/upstream/main)" = "$(git rev-parse clean)" ] ||
    fail 'the fixture does not pick the base without the finding for HEAD first'
[ "$(git merge-base refs/remotes/upstream/main HEAD)" = "$(git rev-parse dirty)" ] ||
    fail 'the fixture does not pick the base with the finding for upstream first'
git config core.hooksPath "$scratch/tools/githooks"
echo 'title: "Title Case"' >> Tinycast/Upstream.swift
git add Tinycast
if git commit --quiet -m 'Ours' > "$scratch/output" 2>&1; then
    fail 'a normal commit was measured against the base that already has the finding'
fi
grep -qx 'error Tinycast/Upstream.swift: Title Case' "$scratch/output" || fail 'the refusal did not name the file'
echo 'PASS: a normal commit with two bases is measured against the one git picks for HEAD first'
