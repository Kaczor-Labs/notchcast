#!/bin/bash
# script-tests: macos (Scripts/run-tests.sh's lockf and a real swiftc harness)
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
# land.sh --guard against a bare origin: main is $base plus the commits each scenario lands; gh is a stub reading $GH.
guard_tests() (
    set -euo pipefail
    export HOME="$scratch/home" NOTCHCAST_LAND_TOOLS=test
    mkdir -p "$scratch/bin" "$HOME/.config/notchcast"
    echo 'notchcast_notify() { cat >> "$GH/notified"; }' > "$HOME/.config/notchcast/private.env"
    cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH/calls"
case "$*" in
    api\ repos/*/commits/*/statuses*) sha=${2#*/commits/}; cat "$GH/followup-${sha%%/*}" 2>/dev/null || echo none ;;
    api\ repos/*/statuses/*) for arg; do case "$arg" in state=*) echo "${arg#state=}" > "$GH/followup-${2##*/}" ;; esac; done ;;
    run\ list*) while [ "$1" != --commit ]; do shift; done; cat "$GH/run-$2" 2>/dev/null || true ;;
    run\ view*--log) echo 'FAILED  1 of 9 harness(es) failed in 3s: FavoritesTests' ;;
    run\ view*) cat "$GH/verdict-$3" ;;
    pr\ create*) echo https://github.com/kaczordodgers/notchcast/pull/99 ;;
    pr\ view*) echo fixture-branch ;;
    pr\ close*|pr\ reopen*) ;;
    *) exit 3 ;;
esac
STUB
    chmod +x "$scratch/bin/gh"
    export PATH="$scratch/bin:$PATH"
    git init --quiet --bare "$scratch/guard.git"
    git clone --quiet --no-hardlinks "$scratch/repo" "$scratch/guard"
    cd "$scratch/guard"
    git remote set-url origin "$scratch/guard.git"
    git config user.name Damian
    git config user.email 336236323+kaczordodgers@users.noreply.github.com
    git fetch --quiet "$scratch/repo" refs/remotes/upstream/main:refs/remotes/upstream/main
    # scenario <commits on $base, oldest first: linux|mac>: main is rebuilt, and gh starts with no verdict and no call.
    scenario() {
        local kind number=6
        export GH=$(mktemp -d "$scratch/gh.XXXXXX")
        : > "$GH/calls"
        git switch --quiet --detach "$base"
        for kind; do
            number=$((number + 1))
            echo "// guard fixture $number" >> Tinycast/Features/Launcher/Model/FavoriteSlots.swift
            git commit --quiet -am "Notchcast: guard fixture (#$number)" -m "Landed-from: $kind"
            git push --quiet --force origin "HEAD:refs/pull/$number/head"
        done
        git push --quiet --force origin HEAD:refs/heads/main
        git push --quiet origin --delete fixture-branch 2>/dev/null || true
        tip=$(git rev-parse HEAD)
    }
    red() { echo 55 > "$GH/run-$1"; echo 'red https://github.com/kaczordodgers/notchcast/actions/runs/55' > "$GH/verdict-55"; }
    main() { git ls-remote origin refs/heads/main | cut -f1; }
    guard() { bash "$land" --guard > "$scratch/guard.log" 2>&1 || { cat "$scratch/guard.log"; exit 1; }; }
    scenario linux
    guard
    [ "$(main)" = "$tip" ] && grep -q 'its macOS run has no verdict yet' "$scratch/guard.log" && [ ! -e "$GH/followup-$tip" ]
    echo 'PASS: guard leaves a Linux landing whose macOS run has no verdict'
    echo 55 > "$GH/run-$tip"; echo green > "$GH/verdict-55"
    guard
    [ "$(main)" = "$tip" ] && [ "$(< "$GH/followup-$tip")" = success ] && ! grep -q 'pr create' "$GH/calls"
    echo 'PASS: guard records a green macOS run and reverts nothing'
    scenario linux
    red "$tip"
    guard
    git fetch --quiet origin main
    reverted=$(git rev-parse FETCH_HEAD)
    [ "$(git rev-parse "$reverted^")" = "$tip" ] || { cat "$scratch/guard.log"; echo 'FAIL: no revert landed on main'; exit 1; }
    [ "$(git diff --name-only "$base" "$reverted")" = notchcast/config.env ]
    git show "$reverted:notchcast/config.env" | grep -q '^LINUX_DENY_INPUTS=".*Tinycast/Features/Launcher/Model/FavoriteSlots.swift"$'
    [ "$(git show -s --format='%(trailers:key=Landed-from,valueonly,separator=)' "$reverted")" = mac ]
    grep -q '^pr create .*--head revert-7 ' "$GH/calls" && grep -q '^pr close 99 ' "$GH/calls" && grep -q '^pr reopen 7 .*actions/runs/55' "$GH/calls"
    [ "$(git ls-remote origin refs/heads/fixture-branch | cut -f1)" = "$tip" ] && [ -z "$(git ls-remote origin refs/heads/revert-7)" ]
    [ "$(< "$GH/followup-$tip")" = failure ] && grep -q '#7 landed from Linux and went red on macOS (FavoritesTests): reverted' "$GH/notified"
    echo 'PASS: red after a sole Linux landing: reverted on main by a revert PR, the PR reopened with the log, its input denied'
    : > "$GH/calls"
    guard
    [ "$(main)" = "$reverted" ] && ! grep -q 'pr \|run ' "$GH/calls"
    echo 'PASS: a judged Linux landing is not judged twice'
    scenario linux mac
    red "$tip"
    guard
    [ "$(main)" = "$tip" ] && ! grep -q 'pr create' "$GH/calls" || { cat "$scratch/guard.log"; echo 'FAIL: reverted with another change on top'; exit 1; }
    [ "$(< "$GH/followup-$(git rev-parse "$tip^")")" = failure ] && grep -q '#7 landed from Linux as .* main is red on macOS: .*actions/runs/55. Not reverted' "$GH/notified"
    echo 'PASS: red with another change after the Linux landing: no revert, the keeper is told'
    scenario linux linux
    red "$tip"
    guard
    [ "$(main)" = "$tip" ] && ! grep -q 'pr create' "$GH/calls" && [ "$(grep -c 'Not reverted' "$GH/notified")" -eq 2 ]
    echo 'PASS: red after two Linux landings: neither is the only change, no revert, the keeper is told of both'
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
)
(
    eval "$(sed -n -e '/^route() {$/,/^}$/p' -e '/^as_maintainer() {$/,/^}$/p' -e '/^stamp() {$/,/^}$/p' "$root/notchcast/land.sh")"
    train=(41 42) check=0 status=0
    notchcast_mac_route() { echo "handed over: $*"; }
    output=$(route 'mac-only: CalcTests') || status=$?
    [ "$status" -eq 4 ] && [[ "$output" == *'ROUTED: #41 42 goes to a Mac, not landed here: mac-only: CalcTests'*'handed over: 41 42'* ]]
    unset -f notchcast_mac_route
    output=$(route 'mac-only: CalcTests') || status=$?
    [ "$status" -eq 4 ] && [[ "$output" == *'No Mac route here'*'notchcast/land.sh 41 42'* ]]
    echo 'PASS: a routed landing exits 4 and goes through the notchcast_mac_route hook, or says how to land it on a Mac'
    cd "$scratch/delete"
    source "$root/notchcast/config.env"
    base=$(git rev-parse HEAD) parent=$base
    for pr in 41 42; do
        printf 'Notchcast: fixture (#%s)\n' "$pr" > "$scratch/message-$pr"
        parent=$(as_maintainer git commit-tree "$base^{tree}" -p "$parent" -F "$scratch/message-$pr")
        echo "$parent" > "$scratch/commit-$pr"
    done
    landed_from=linux
    stamp
    [ "$tip" = "$(< "$scratch/commit-42")" ] && [ "$(git rev-parse "$tip^")" = "$(< "$scratch/commit-41")" ] && [ "$(git rev-parse "$tip^^")" = "$base" ]
    [ "$(git log --format='%s|%(trailers:key=Landed-from,valueonly,separator=)' "$base..$tip" | tr '\n' ' ')" = 'Notchcast: fixture (#42)|linux Notchcast: fixture (#41)|linux ' ]
    echo 'PASS: every commit of a landed chain says where its harness proof ran (Landed-from)'
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
    printf '#!/bin/bash\n"$(dirname "$0")/changed-harnesses-full.sh" "$@" | { grep -x -e notchcast-hidden-features-test -e FavoritesTests || true; }\n' \
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
# The three ways a landing started on Linux ends; NOTCHCAST_PLATFORM plays Linux on a Mac too.
favorites=Tinycast/Features/Launcher/Model/FavoriteSlots.swift
git switch --quiet -c linux-ok "$base"
echo '// landing fixture' >> "$favorites"
git commit --quiet -am 'Fixture: an input of a linux-ok harness'
linux_ok=$(git rev-parse HEAD)
NOTCHCAST_PLATFORM=Linux "$land" --check "$base" "$linux_ok" > "$scratch/linux.log" 2>&1 || { cat "$scratch/linux.log"; exit 1; }
grep -q 'every harness this diff reaches is linux-ok; proving it here on 1 of them' "$scratch/linux.log"
grep -q 'ok .*FavoritesTests' "$scratch/linux.log" && grep -q 'PASS: merged-tree harnesses' "$scratch/linux.log"
echo 'PASS: every reached harness linux-ok: Linux proves the merged tree itself'
git switch --quiet -c linux-mac "$linux_ok"
echo '// landing fixture' >> Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
git commit --quiet -am 'Fixture: an input of a mac-only harness too'
status=0
NOTCHCAST_PLATFORM=Linux "$land" --check "$base" HEAD > "$scratch/linux.log" 2>&1 || status=$?
[ "$status" -eq 4 ] || { cat "$scratch/linux.log"; exit 1; }
grep -q 'ROUTED: this diff lands from a Mac, not from Linux: mac-only: .*notchcast-hidden-features-test' "$scratch/linux.log"
! grep -q 'FavoritesTests  ' "$scratch/linux.log"
echo 'PASS: one mac-only harness reached: routed to a Mac, nothing run on Linux'
git switch --quiet -c linux-red "$base"
echo 'let landingFixture: Int = ""' >> "$favorites"
git commit --quiet -am 'Fixture: break a linux-ok harness'
status=0
NOTCHCAST_PLATFORM=Linux "$land" --check "$base" HEAD > "$scratch/linux.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'REFUSED: FavoritesTests failed' "$scratch/linux.log" || { cat "$scratch/linux.log"; exit 1; }
echo 'PASS: the Linux run red: refused'
guard_tests
if [ "$(uname -s)" != Darwin ]; then
    echo 'SKIPPED off a Mac: the two-PR merged-tree fixtures, which compile the mac-only notchcast-hidden-features-test'
else
git switch --quiet -c fixture-a "$base"
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
fi
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
