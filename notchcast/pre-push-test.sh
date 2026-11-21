#!/bin/bash
# githooks/pre-push on fixture remotes: an orphan branch, a new branch and a normal branch are each checked over
# exactly what the push adds, and a non-allowed identity in that range is refused with a reason.
set -euo pipefail
export LC_ALL=C
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { echo "FAIL: $1"; [ ! -s "$scratch/output" ] || cat "$scratch/output"; exit 1; }
email=$(sed -n 's/^MAINTAINER_EMAIL=//p' "$root/notchcast/config.env")
export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture GIT_AUTHOR_EMAIL=$email GIT_COMMITTER_EMAIL=$email
mkdir "$scratch/bin"
if ! command -v gitleaks > /dev/null && [ ! -x /opt/homebrew/bin/gitleaks ]; then
    printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/gitleaks"
    chmod +x "$scratch/bin/gitleaks"
fi
export PATH="$scratch/bin:$PATH"
git init --quiet --bare -b main "$scratch/upstream.git"
git init --quiet --bare -b main "$scratch/origin.git"
git init --quiet -b main "$scratch/work"
cd "$scratch/work"
git remote add upstream "$scratch/upstream.git"
git remote add origin "$scratch/origin.git"
# commit <name> [email]: one commit adding <name>.txt, by the allowed identity unless an email is given.
commit() {
    echo "$1" > "$1.txt"
    git add "$1.txt"
    GIT_AUTHOR_EMAIL=${2:-$email} GIT_COMMITTER_EMAIL=${2:-$email} git commit --quiet -m "$1"
}
commit upstream-seed
git push --quiet upstream main
commit fork
git push --quiet origin main
git switch --quiet -c normal
commit normal-old
git push --quiet origin normal
git switch --quiet --orphan evidence
commit evidence-old public@example.invalid
git push --quiet origin evidence
git fetch --quiet upstream
# The hook runs from this fixture's root, so it finds the real checkers there; the drift gates only warn and are skipped.
mkdir -p notchcast/githooks
cp "$root/notchcast/githooks/pre-push" notchcast/githooks/
for tool in check-identity.sh check-identity.py check-commit-emails.py ci.py config.env merge-main-check.sh fork-point.sh merge-words.py; do
    ln -s "$root/notchcast/$tool" "notchcast/$tool"
done
printf 'import sys\nsys.exit(0)\n' > notchcast/check-drift.py
printf '%s\n' notchcast/ >> .git/info/exclude
git config core.hooksPath notchcast/githooks
# push <branch>: pushes the checked-out HEAD through the hook; status and output for the checks below.
push() {
    status=0
    git push origin "HEAD:refs/heads/$1" > "$scratch/output" 2>&1 || status=$?
}
# passes <branch> <commits>: the push passes, checking exactly <commits> commits.
passes() {
    push "$1"
    [ "$status" -eq 0 ] || fail "a clean push to $1 was refused"
    grep -q "^Checked $2 commits; 0 non-allowed identities" "$scratch/output" || fail "the push to $1 did not check exactly its $2 new commits"
}
# refuses <branch>: a new commit by a non-allowed identity is refused with a reason, then dropped.
refuses() {
    commit "$1-bad" stranger@example.invalid
    push "$1"
    [ "$status" -ne 0 ] || fail "a non-allowed identity pushed to $1 passed"
    grep -q 'non-allowed author email' "$scratch/output" && grep -q '^pre-push: REFUSED: ' "$scratch/output" \
        || fail "the refused push to $1 did not say why"
    git reset --quiet --hard HEAD~1
}

commit evidence-new
passes evidence 1
refuses evidence
echo 'PASS: an orphan branch is checked from the remote tip only, and a bad identity there is refused'

git switch --quiet -c feature main
commit feature-one
commit feature-two
refuses feature
passes feature 3
echo 'PASS: a new branch is checked from its upstream merge base, and a bad identity there is refused'

git switch --quiet normal
commit normal-new
refuses normal
passes normal 3
echo 'PASS: a normal branch is checked from its upstream merge base, and a bad identity there is refused'

git switch --quiet --orphan rootless
commit rootless
push rootless
[ "$status" -ne 0 ] && grep -q '^pre-push: REFUSED: refs/heads/rootless would add root commit' "$scratch/output" \
    || fail 'a new root commit was not refused with a reason'
echo 'PASS: a new branch with no history to check from is refused with a reason'
