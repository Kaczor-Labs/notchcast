#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
sync_wait_tests() (
    set -euo pipefail
    source "$root/notchcast/sync-wait.sh"
    declare -f wait_for_sync >/dev/null || { echo 'FAIL: Sync wait helper missing'; exit 1; }
    refuse() { echo "REFUSED: $*"; exit 1; }
    export NOTCHCAST_TEST_SYNC_POLL_SECONDS=1 NOTCHCAST_TEST_SYNC_LIMIT_SECONDS=2
    sleeps=0
    sleep() { sleeps=$((sleeps + 1)); SECONDS=$((SECONDS + $1)); }
    gh() {
        if [ "$2" = list ]; then
            [[ "$*" == *'--workflow sync.yml'* ]] || exit 1
            [[ "$*" == *'--status queued'* || "$*" == *'--status in_progress'* ]] || exit 1
            [ "$scenario" != none ] && echo 123
            return 0
        fi
        [[ "$*" == *'--json jobs --jq '* ]] || exit 1
        [ "$scenario" != broken ] || return 1
        case "$scenario" in
            main) echo '{"jobs":[{"name":"main","status":"in_progress"}]}' ;;
            gone) if [ "$sleeps" -eq 0 ]; then echo '{"jobs":[{"name":"replay","status":"in_progress"}]}'; else echo '{"jobs":[]}'; fi ;;
            queued) echo '{"jobs":[{"name":"replay","status":"queued"}]}' ;;
            plan-queued) echo '{"jobs":[{"name":"plan","status":"queued"}]}' ;;
            planning) if [ "$sleeps" -eq 0 ]; then echo '{"jobs":[{"name":"plan","status":"in_progress"}]}'
                else echo '{"jobs":[{"name":"plan","status":"completed","conclusion":"success"},{"name":"main","status":"in_progress"}]}'; fi ;;
            planned) if [ "$sleeps" -eq 0 ]; then echo '{"jobs":[{"name":"plan","status":"completed","conclusion":"success"}]}'
                else echo '{"jobs":[{"name":"plan","status":"completed","conclusion":"success"},{"name":"replay","status":"completed"}]}'; fi ;;
            *) echo '{"jobs":[{"name":"replay","status":"in_progress"}]}' ;;
        esac | jq "${@: -1}"
    }
    for scenario in none main gone plan-queued planning planned; do
        sleeps=0
        wait_for_sync
        case "$scenario" in gone|planning|planned) [ "$sleeps" -eq 1 ] ;; *) [ "$sleeps" -eq 0 ] ;; esac
        echo "PASS: Sync $scenario"
    done
    for scenario in forever queued; do
        sleeps=0
        output=$(wait_for_sync) && exit 1
        [[ "$output" == *'REFUSED: Sync run 123 (plan or replay) still running after 40 min; try again'* ]]
        echo "PASS: Sync $scenario refuses at limit"
    done
    scenario=broken
    output=$(wait_for_sync) && exit 1
    [[ "$output" == *'REFUSED: could not read Sync run 123'* ]]
    echo 'PASS: Sync unreadable run refuses'
)
pr=42
sync_wait_tests
if [ "${1:-}" = --sync ]; then exit 0; fi
mkdir -p "${NOTCHCAST_SCRATCH:=$HOME/Library/Caches/notchcast}"
scratch=$(mktemp -d "$NOTCHCAST_SCRATCH/land-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
source "$root/notchcast/local-build-status.sh"
gh() { jq -s "${@: -1}" "$status_fixture"; }
status_fixture="$scratch/status"
printf '%s\n' '{"id":1,"context":"build/local","creator":{"login":"kaczordodgers"},"url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/head","state":"success"}' > "$status_fixture"
local_build_green head
echo 'PASS: local success accepted'
if local_build_green other; then exit 1; fi
echo 'PASS: different sha refused'
printf '%s\n' '{"id":2,"context":"build/local","creator":{"login":"kaczordodgers"},"url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/head","state":"failure"}' >> "$status_fixture"
if local_build_green head; then exit 1; fi
echo 'PASS: local failure refused'
printf '%s\n' '{"id":1,"context":"build/local","url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/head","state":"success","creator":{"login":"other"}}' > "$status_fixture"
if local_build_green head; then exit 1; fi
echo 'PASS: other creator refused'
rm "$status_fixture"
unset -f gh
(
    eval "$(sed -n '/^delete_head() {$/,/^}$/p' "$root/notchcast/land.sh")"
    # A fake gh: PR 7 is based on stacked; its retarget logs whether origin/stacked still existed.
    gh() {
        case "$*" in
            "pr list -R $FORK_REPO --base stacked --state open "*) echo 7 ;;
            "pr list -R $FORK_REPO --base unlistable "*) return 1 ;;
            "pr list -R $FORK_REPO --base "*) ;;
            "pr edit 7 -R $FORK_REPO --base main")
                echo "edit 7 $(git ls-remote origin refs/heads/stacked | wc -l | tr -d ' ')" >> "$scratch/gh.log"
                [ -z "${edit_fails:-}" ] ;;
            *) echo "unexpected gh $*" >&2; return 1 ;;
        esac
    }
    git init --quiet --bare "$scratch/remote.git"
    git clone --quiet "$scratch/remote.git" "$scratch/delete"
    cd "$scratch/delete"
    git -c user.name=Fixture -c user.email=fixture@example.com commit --quiet --allow-empty -m base
    head=$(git rev-parse HEAD)
    git branch matching
    git push --quiet origin matching
    delete_head matching "$head"
    [ -z "$(git ls-remote origin refs/heads/matching)" ]
    ! git show-ref --verify --quiet refs/heads/matching
    git -c user.name=Fixture -c user.email=fixture@example.com commit --quiet --allow-empty -m moved
    moved=$(git rev-parse HEAD)
    git branch remote-moved
    git push --quiet origin remote-moved
    delete_head remote-moved "$head"
    [ "$(git ls-remote origin refs/heads/remote-moved | cut -f1)" = "$moved" ]
    git branch local-moved
    git push --quiet origin "$head:refs/heads/local-moved"
    delete_head local-moved "$head"
    [ "$(git rev-parse local-moved)" = "$moved" ]
    delete_head remote-moved "$moved" true
    [ -n "$(git ls-remote origin refs/heads/remote-moved)" ]
    echo 'PASS: delete_head matching, moved remote, moved local and fork'
    git push --quiet origin "$head:refs/heads/stacked"
    edit_fails=1
    output=$(delete_head stacked "$head" 2>&1)
    [ "$(git ls-remote origin refs/heads/stacked | cut -f1)" = "$head" ]
    [[ "$output" == *'WARN: kept origin/stacked: PR #7 still targets it'* ]]
    echo 'PASS: delete_head keeps a branch whose stacked PR could not move to main'
    edit_fails=
    delete_head stacked "$head"
    [ "$(tail -1 "$scratch/gh.log")" = 'edit 7 1' ]
    [ -z "$(git ls-remote origin refs/heads/stacked)" ]
    echo 'PASS: delete_head moves a stacked PR to main before deleting its base'
    git push --quiet origin "$head:refs/heads/unlistable"
    output=$(delete_head unlistable "$head" 2>&1)
    [ -n "$(git ls-remote origin refs/heads/unlistable)" ]
    [[ "$output" == *'WARN: kept origin/unlistable: cannot list PRs based on it'* ]]
    echo 'PASS: delete_head keeps a branch when it cannot list the PRs based on it'
)
if [ "${1:-}" = --statuses ]; then
    echo 'PASS: local build status fixtures'
    exit 0
fi
git clone --quiet --no-hardlinks "$root" "$scratch/repo"
cd "$scratch/repo"
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
printf '#!/usr/bin/env python3\n' > notchcast/check-drift.py
printf '#!/usr/bin/env python3\n' > notchcast/check-drift-test.py
git add notchcast/check-drift.py notchcast/check-drift-test.py
git commit --quiet -m 'Fixture: isolate drift gates covered by land-drift-test.py'
base=$(git rev-parse HEAD)
# land.sh refreshes upstream main: the fixture serves this checkout's upstream/main to itself, so CI's checkout,
# which has no main branch, runs it too.
git fetch --quiet "$root" refs/remotes/upstream/main
git switch --quiet --detach
git update-ref refs/heads/main FETCH_HEAD
git remote add upstream "$scratch/repo"
# Each landing runs only the harness the fixtures break; --full keeps the whole selection (97 harnesses, twice).
land="$root/notchcast/land.sh"
if [ "${1:-}" != --full ]; then
    cp -R "$root/notchcast" "$scratch/tools"
    mv "$scratch/tools/changed-harnesses.sh" "$scratch/tools/changed-harnesses-full.sh"
    printf '#!/bin/bash\n"$(dirname "$0")/changed-harnesses-full.sh" "$@" | { grep -x notchcast-hidden-features-test || true; }\n' \
        > "$scratch/tools/changed-harnesses.sh"
    chmod +x "$scratch/tools/changed-harnesses.sh"
    land="$scratch/tools/land.sh"
fi
# A Sync rewrite: old main has our commit; new main is upstream's next commit plus the same change replayed.
fixture_commit() {
    printf '%s\n' "$2" > "notchcast/$1.fixture"
    git add "notchcast/$1.fixture"
    git commit --quiet -m "Fixture: $1 $2"
}
git switch --quiet -c fork-old "$base"
fixture_commit ours old
old=$(git rev-parse HEAD)
git switch --quiet -c fork-new "$base"
fixture_commit upstream new
fixture_commit ours old
new=$(git rev-parse HEAD)
git switch --quiet -c fork-clean "$old"
fixture_commit ours edited
clean=$(git rev-parse HEAD)
git switch --quiet -c fork-conflict "$old"
fixture_commit upstream pr
conflict=$(git rev-parse HEAD)
status=0
"$land" --check "$new" "$clean" > "$scratch/fork.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'REFUSED: merge conflict: notchcast/ours.fixture' "$scratch/fork.log"
echo 'PASS: without a recorded tip, a PR from before the rewrite conflicts with its own replayed commit'
git update-ref "refs/notchcast/synced/$old" "$old"
git update-ref "refs/notchcast/synced/$new" "$new"
"$land" --check "$new" "$clean" > "$scratch/fork.log" 2>&1 || { cat "$scratch/fork.log"; exit 1; }
grep -q "merging from ${old:0:8}" "$scratch/fork.log"
echo 'PASS: a PR from before the rewrite lands from its recorded fork point, past a newer recorded tip'
status=0
"$land" --check "$new" "$conflict" > "$scratch/fork.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'REFUSED: merge conflict: notchcast/upstream.fixture' "$scratch/fork.log"
echo 'PASS: a real conflict from the recorded fork point still refuses'
git switch --quiet -c fork-updated "$old"
git merge --quiet --no-edit "$new"
fixture_commit pr updated
updated=$(git rev-parse HEAD)
git switch --quiet -c fork-newer "$new"
fixture_commit upstream newer
"$land" --check HEAD "$updated" > "$scratch/fork.log" 2>&1 || { cat "$scratch/fork.log"; exit 1; }
if grep -q 'merging from' "$scratch/fork.log"; then cat "$scratch/fork.log"; exit 1; fi
echo 'PASS: a PR from before the rewrite that merged the new main lands by a plain merge'
git for-each-ref --format='delete %(refname)' refs/notchcast/synced/ | git update-ref --stdin
if [ "${1:-}" = --fork ]; then exit 0; fi
git switch --quiet -c fixture-a
python3 - <<'PY'
import re
from pathlib import Path
for p in [*Path('Tinycast').rglob('*.swift'), *Path('Tests').glob('*.swift')]:
    s = p.read_text()
    if p.name == 'NotchcastHidden.swift':
        p.write_text(re.sub(r'\btabs\b', 'hiddenTabs', s))
    elif 'NotchcastHidden.tabs' in s:
        p.write_text(s.replace('NotchcastHidden.tabs', 'NotchcastHidden.hiddenTabs'))
PY
git commit --quiet -am 'Fixture: rename the hidden tab set'
a=$(git rev-parse HEAD)
"$root/notchcast/changed-harnesses.sh" "$base" "$a" > "$scratch/selected"
grep -x notchcast-hidden-features-test "$scratch/selected"
grep -x SettingsHistoryTests "$scratch/selected"
"$land" --check "$base" "$a" > "$scratch/a.log" 2>&1 || { cat "$scratch/a.log"; exit 1; }
echo 'PASS: A alone'
git switch --quiet -c fixture-b "$base"
python3 - <<'PY'
from pathlib import Path
p = Path('Tinycast/Features/Notchcast/Hidden/LandingFixture.swift')
p.write_text('func landingFixture() -> Bool { NotchcastHidden.tabs.isEmpty }\n')
p = Path('Tests/notchcast-hidden-features-test.swift')
p.write_text('// notchcast-sources: Tinycast/Features/Notchcast/Hidden/LandingFixture.swift\n' + p.read_text())
PY
git add Tinycast/Features/Notchcast/Hidden/LandingFixture.swift Tests/notchcast-hidden-features-test.swift
git commit --quiet -m 'Fixture: add a consumer of the old name'
b=$(git rev-parse HEAD)
"$land" --check "$base" "$b" > "$scratch/b.log" 2>&1 || { cat "$scratch/b.log"; exit 1; }
echo 'PASS: B alone'
git merge --quiet --no-commit --no-ff "$a"
git merge --abort
echo 'PASS: A and B merge without text conflicts'
status=0
"$land" --check "$b" "$a" > "$scratch/combined.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: notchcast-hidden-features-test failed' "$scratch/combined.log"
edit_config() {
    echo "$1" >> notchcast/config.env
    git add notchcast/config.env
    git commit --quiet -m "Fixture: $1"
}
git switch --quiet -c fixture-ours "$base"
edit_config '# ours'
ours=$(git rev-parse HEAD)
git switch --quiet -c fixture-conflict "$base"
edit_config '# theirs'
status=0
"$land" --check "$ours" HEAD > "$scratch/conflict.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep 'REFUSED: merge conflict' "$scratch/conflict.log"
echo 'PASS: land-test.sh'
