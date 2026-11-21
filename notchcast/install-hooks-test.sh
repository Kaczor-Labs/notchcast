#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { echo "FAIL: $1"; cat "$scratch/output"; exit 1; }
email=$(sed -n 's/^MAINTAINER_EMAIL=//p' "$root/notchcast/config.env")
export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture GIT_AUTHOR_EMAIL=$email GIT_COMMITTER_EMAIL=$email
if ! command -v gitleaks >/dev/null && [ ! -x /opt/homebrew/bin/gitleaks ]; then
    mkdir "$scratch/bin"
    printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/gitleaks"
    chmod +x "$scratch/bin/gitleaks"
    export PATH="$scratch/bin:$PATH"
fi

git init --quiet --bare -b main "$scratch/origin.git"
git init --quiet --bare -b main "$scratch/upstream.git"
git init --quiet -b main "$scratch/work"
cd "$scratch/work"
git remote add origin "$scratch/origin.git"
git remote add upstream "$scratch/upstream.git"
git commit --quiet --allow-empty -m upstream
git push --quiet upstream main
mkdir -p notchcast/githooks
cp "$root/notchcast/githooks/"* notchcast/githooks/
for tool in install-hooks.sh check-identity.sh check-identity.py check-commit-emails.py ci.py config.env merge-main-check.sh; do
    cp "$root/notchcast/$tool" notchcast/
done
printf 'pass\n' > notchcast/check-drift.py
git add notchcast
git commit --quiet -m 'Main tools'
git push --quiet origin main

git worktree add --quiet -b stale "$scratch/stale"
printf '#!/bin/sh\nexit 0\n' > "$scratch/stale/notchcast/githooks/pre-push"
git -C "$scratch/stale" commit --quiet -am 'Old hook fixture'
git worktree add --quiet --detach "$scratch/evidence"
git -C "$scratch/evidence" switch --quiet --orphan evidence
git -C "$scratch/evidence" commit --quiet --allow-empty -m 'Evidence seed'
git -C "$scratch/evidence" push --quiet origin evidence
seed=$(git -C "$scratch/evidence" rev-parse HEAD)
bad=$(GIT_AUTHOR_EMAIL=stranger@example.invalid git commit-tree "$seed^{tree}" -p "$seed" -m 'Bad identity fixture')

# Ask Git which hook it runs with the relative setting, without publishing anything.
git config --local core.hooksPath notchcast/githooks
if git -C "$scratch/evidence" hook run pre-push > "$scratch/output" 2>&1; then
    fail 'relative path unexpectedly found a pre-push hook in the orphan worktree'
fi
grep -q 'cannot find a hook named pre-push' "$scratch/output" || fail 'unexpected relative path result'
git -C "$scratch/stale" hook run pre-push > "$scratch/output" 2>&1 || fail 'old hook fixture failed'
echo 'PASS: the relative setting finds no orphan hook and uses the old stub on a stale branch'

./notchcast/install-hooks.sh
./notchcast/install-hooks.sh
for worktree in evidence stale; do
    if git -C "$scratch/$worktree" push origin "$bad:refs/heads/evidence" > "$scratch/output" 2>&1; then
        fail "$worktree pushed a non-allowed identity"
    fi
    if ! grep -q 'non-allowed author email' "$scratch/output" || ! grep -q '^pre-push: REFUSED: ' "$scratch/output"; then
        fail "$worktree refusal did not name the identity check"
    fi
    [ "$(git --git-dir="$scratch/origin.git" rev-parse evidence)" = "$seed" ] || fail 'remote evidence ref moved'
    echo "PASS: $worktree push refused by main's identity check"
done

cd "$scratch/evidence"
printf '%s\n' 'local staged data' > staged.txt
git add staged.txt
if GIT_AUTHOR_EMAIL=stranger@example.invalid git commit -m 'Bad staged identity' > "$scratch/output" 2>&1; then
    fail 'the orphan worktree committed a non-allowed identity'
fi
grep -q 'author: non-allowed email' "$scratch/output" || fail 'pre-commit did not check the worktree identity'
if git commit -m "/Us""ers/fixture/notes" > "$scratch/output" 2>&1; then
    fail 'the orphan worktree committed a forbidden message'
fi
grep -q 'commit message: <home-path>' "$scratch/output" || fail 'commit-msg did not check the worktree message'
git commit --quiet -m 'Clean evidence' > "$scratch/output" 2>&1 || fail 'clean orphan commit was refused'
# A push must refresh even when this clone still records the commit from before the installer shipped.
git update-ref refs/remotes/origin/main refs/remotes/upstream/main
git push --quiet origin evidence > "$scratch/output" 2>&1 || fail 'clean orphan push was refused'
grep -q '^Checked 1 commits; 0 non-allowed identities' "$scratch/output" || fail 'clean push did not run the hook'
[ "$(git --git-dir="$scratch/origin.git" rev-parse evidence)" = "$(git rev-parse HEAD)" ] || fail 'clean push did not update origin'
git config --local --unset merge.notchcast-words.driver || true
git worktree add --quiet --detach "$scratch/fresh"
git config --get merge.notchcast-words.driver > "$scratch/output" || fail 'post-checkout did not register the merge driver'
echo 'PASS: main checks commits, refreshes for clean pushes and registers the merge driver from linked worktrees'
