#!/bin/bash
# merge-main-check.sh on a fixture origin: a merge of main is refused unless it resolves a real conflict.
set -euo pipefail
export LC_ALL=C
root=$(git rev-parse --show-toplevel)
check="$root/notchcast/merge-main-check.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { echo "FAIL: $1"; [ ! -s "$scratch/output" ] || cat "$scratch/output"; exit 1; }
git init --quiet -b main "$scratch/work"
cd "$scratch/work"
git config user.name Fixture
git config user.email fixture@example.invalid
mkdir notchcast
printf '%s\n' 'notchcast/config.env merge=notchcast-words' 'registry.txt merge=union' > .gitattributes
printf '%s\n' keep old > registry.txt
echo 'LIST="one two"' > notchcast/config.env
echo base > shared.txt
echo readme > README.md
git add .
git commit --quiet -m seed
git init --quiet --bare "$scratch/origin.git"
git remote add origin "$scratch/origin.git"
git push --quiet origin main
# branch <name> <file> <text>: a PR branch off origin's main with one commit, pushed; leaves it checked out.
branch() {
    git switch --quiet -c "$1" origin/main
    echo "$3" > "$2"
    git add "$2"
    git commit --quiet -m "$1"
    git push --quiet origin "$1"
}
# main_moves <file> <text>: origin's main gets one commit.
main_moves() {
    git switch --quiet --detach origin/main
    echo "$2" > "$1"
    git add "$1"
    git commit --quiet -m "main: $1"
    git push --quiet origin HEAD:main
    git fetch --quiet origin
}
# verdict <branch>: runs the check as pre-push would for pushing the checked-out HEAD to <branch>.
verdict() {
    status=0
    bash "$check" "$(git rev-parse HEAD)" "refs/heads/$1" "$(git rev-parse "origin/$1")" > "$scratch/output" 2>&1 || status=$?
}

branch clean clean.txt clean
main_moves other.txt other
git switch --quiet clean
git merge --quiet --no-edit origin/main
verdict clean
[ "$status" -eq 1 ] && grep -q "^REFUSED: this push merges main into clean ($(git rev-parse --short=8 HEAD)), and clean at .* merges onto main without a conflict; .* Drop the merge: git rebase --onto $(git rev-parse --short=8 HEAD)^1 $(git rev-parse --short=8 HEAD), then push again," "$scratch/output" \
    || fail 'a merge of main into a branch that merged cleanly was not refused'
eval "$(sed -n 's/.*Drop the merge: \(git rebase --onto [^,]*\),.*/\1/p' "$scratch/output") --quiet"
echo again >> clean.txt
git commit --quiet -am 'more work'
verdict clean
[ "$status" -eq 0 ] || fail 'the branch after the named rebase dropped the merge was still refused'
echo 'PASS: merging main into a branch that merges onto main cleanly is refused, and the command it names clears it'

branch words notchcast/config.env 'LIST="one two words"'
main_moves notchcast/config.env 'LIST="zero one two"'
git switch --quiet words
git merge --quiet --no-edit origin/main > /dev/null 2>&1 || { git checkout --quiet --theirs notchcast/config.env; git commit --quiet --no-edit -a; }
verdict words
[ "$status" -eq 1 ] && grep -q '^REFUSED: this push merges main into words' "$scratch/output" \
    || fail 'a merge of main the word merge rule makes unnecessary was not refused'
echo 'PASS: the word merge rule counts: two additions to one marked line are no conflict'

branch generated README.md 'branch readme'
main_moves README.md 'main readme'
git switch --quiet generated
git merge --quiet --no-edit origin/main > /dev/null 2>&1 || { git checkout --quiet --theirs README.md; git commit --quiet --no-edit -a; }
verdict generated
[ "$status" -eq 1 ] || fail 'a merge of main conflicting only in a generated file, which landing takes from main, was not refused'
echo 'PASS: a conflict only in a generated file is no conflict'

branch real shared.txt branch
main_moves shared.txt main
git switch --quiet real
git merge --quiet --no-edit origin/main > /dev/null 2>&1 || true
echo resolved > shared.txt
git commit --quiet --no-edit -a
verdict real
[ "$status" -eq 0 ] || fail 'a merge of main that resolves a real conflict was refused'
echo 'PASS: a merge of main that resolves a real conflict passes'

branch revive registry.txt keep
main_moves registry.txt "$(printf '%s\n' keep old appended)"
git switch --quiet revive
git merge --quiet --no-edit origin/main > /dev/null 2>&1
printf '%s\n' keep appended > registry.txt
git commit --quiet -am 'keep the deletion'
verdict revive
[ "$status" -eq 0 ] || fail 'a merge of main that fixes a line the union merge revives was refused, though the train refuses that union merge'
echo 'PASS: a union merge that revives a deleted line counts as a real conflict, as the train judges it'

# Sync rewrites main and keeps the old tip under refs/notchcast/synced/ on origin, which a plain fetch leaves out.
git switch --quiet --detach origin/main
rewrite_base=$(git rev-parse HEAD)
echo old-main > sync.txt
git add sync.txt
git commit --quiet -m 'old main'
old_main=$(git rev-parse HEAD)
git push --quiet origin HEAD:main
git fetch --quiet origin
branch sync sync.txt branch
git switch --quiet --detach "$rewrite_base"
echo rewritten > rewrite.txt
git add rewrite.txt
git commit --quiet -m 'main after a Sync rewrite'
git push --quiet --force origin HEAD:main "$old_main:refs/notchcast/synced/$old_main"
git fetch --quiet origin
[ -z "$(git for-each-ref refs/notchcast/synced/)" ] || fail 'the fixture clone already has the synced refs'
git switch --quiet sync
git merge --quiet --no-edit origin/main
verdict sync
[ "$status" -eq 0 ] || fail 'a merge of main into a branch cut before a Sync rewrite, which the train merges from its fork point with a conflict, was refused'
echo 'PASS: a branch cut before a Sync rewrite is judged from its fork point, with the synced refs fetched'

branch plain plain.txt plain
echo more >> plain.txt
git commit --quiet -am more
verdict plain
[ "$status" -eq 0 ] || fail 'a plain commit was refused'
branch other other-branch.txt other
git switch --quiet plain
git merge --quiet --no-edit origin/other
verdict plain
[ "$status" -eq 0 ] || fail 'a merge of another PR branch was refused'
git switch --quiet clean
git merge --quiet --no-edit origin/main
for args in "refs/heads/new $(printf '0%.0s' {1..40})" "refs/heads/main $(git rev-parse origin/main)"; do
    status=0
    bash "$check" "$(git rev-parse HEAD)" $args > "$scratch/output" 2>&1 || status=$?
    [ "$status" -eq 0 ] || fail "a push to $args was refused"
done
echo 'PASS: plain commits, a merge of another branch, a new branch and a push to main pass'
