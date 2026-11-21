#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
git init -q
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
git commit -q --allow-empty -m 'Fixture base'
base=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$base"
printf '%s%s\n' private hq > public.txt
git add public.txt
git commit -q -m 'Fixture public addition'
git rm -q public.txt
git commit -q -m 'Fixture public removal'
git update-ref refs/remotes/origin/main HEAD
if ! python3 "$root/notchcast/check-identity.py" history "$base" > "$scratch/output"; then
    cat "$scratch/output"
    echo 'FAIL: already-public forbidden addition refused'
    exit 1
fi
echo 'PASS: already-public forbidden addition ignored'
printf '%s%s\n' private hq > fixture.txt
git add fixture.txt
git commit -q -m 'Fixture addition'
git rm -q fixture.txt
git commit -q -m 'Fixture removal'
if python3 "$root/notchcast/check-identity.py" history "$base" > "$scratch/output"; then
    echo 'FAIL: intermediate forbidden addition accepted'
    exit 1
fi
grep -q '<forbidden-name>' "$scratch/output"
echo 'PASS: intermediate forbidden addition refused'
git switch -q --detach "$base"
mkdir notchcast
printf '%s%s\n' private hq > notchcast/check-identity.py
git add .
git commit -q -m 'Fixture allow list'
python3 "$root/notchcast/check-identity.py" history "$base"
echo 'PASS: allow-listed path accepted'
git switch -q --detach refs/remotes/origin/main
old_tip=$(git rev-parse HEAD)
git switch -q --detach "$base"
git commit -q --allow-empty -m 'Fixture upstream advance'
git cherry-pick "$base..$old_tip" > "$scratch/git-output"
git update-ref refs/remotes/origin/main HEAD
git switch -q --detach "$old_tip"
git commit -q --allow-empty -m 'Fixture clean branch commit'
if ! python3 "$root/notchcast/check-identity.py" history "$base" > "$scratch/output"; then
    cat "$scratch/output"
    echo 'FAIL: rewritten public history refused'
    exit 1
fi
echo 'PASS: rewritten public history ignored'
printf '%s%s\n' private hq > readded.txt
git add readded.txt
git commit -q -m 'Fixture forbidden re-addition'
git rm -q readded.txt
git commit -q -m 'Fixture re-addition removal'
if python3 "$root/notchcast/check-identity.py" history "$base" > "$scratch/output"; then
    echo 'FAIL: forbidden re-addition after rewrite accepted'
    exit 1
fi
grep -q '<forbidden-name>' "$scratch/output"
echo 'PASS: forbidden re-addition after rewrite refused'
git switch -q --detach "$base"
printf 'x\f@@ y\n' > shot.png
git add shot.png
git commit -q -m 'Fixture binary with a form feed'
python3 "$root/notchcast/check-identity.py" history "$base"
echo 'PASS: binary addition with a form feed before @@ scanned'
printf 'x\f%s%s\n' private hq > hidden.png
git add hidden.png
git commit -q -m 'Fixture forbidden name after a form feed'
if python3 "$root/notchcast/check-identity.py" history "$base" > "$scratch/output"; then
    echo 'FAIL: forbidden name after a form feed accepted'
    exit 1
fi
grep -q '<forbidden-name>' "$scratch/output"
echo 'PASS: forbidden name after a form feed refused'
git switch -q --orphan evidence
git rm -rqf . 2>/dev/null || true
printf '%s%s\n' private hq > old-evidence.txt
git add old-evidence.txt
git commit -q -m 'Fixture old evidence'
old_evidence=$(git rev-parse HEAD)
printf 'png\n' > new-shot.png
git add new-shot.png
git commit -q -m 'Fixture new evidence'
if ! python3 "$root/notchcast/check-identity.py" history "$old_evidence" > "$scratch/output"; then
    cat "$scratch/output"
    echo 'FAIL: push to a branch unrelated to main rescanned its public history'
    exit 1
fi
echo 'PASS: push to a branch unrelated to main scans only the pushed range'
printf '%s%s\n' private hq > new-evidence.txt
git add new-evidence.txt
git commit -q -m 'Fixture forbidden new evidence'
if python3 "$root/notchcast/check-identity.py" history "$old_evidence" > "$scratch/output"; then
    echo 'FAIL: forbidden addition on a branch unrelated to main accepted'
    exit 1
fi
grep -q '<forbidden-name>' "$scratch/output"
echo 'PASS: forbidden addition on a branch unrelated to main refused'
git update-ref -d refs/remotes/origin/main
if python3 "$root/notchcast/check-identity.py" history "$base" > "$scratch/output" 2>&1; then
    echo 'FAIL: missing base accepted'
    exit 1
fi
grep -q 'unable to complete scan' "$scratch/output"
echo 'PASS: missing base refused'
