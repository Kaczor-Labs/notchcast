#!/bin/bash
# land.sh <pr>... end to end on a fixture origin: real merges, squash chain and push; gh, swiftc and the checks are stubs.
set -euo pipefail
export LC_ALL=C
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
set -a
source "$root/notchcast/config.env"
set +a
seed="$scratch/seed"
mkdir -p "$scratch/bin" "$scratch/home" "$seed/notchcast" "$seed/Scripts" "$seed/Tests" "$seed/src" "$seed/Tinycast/Features/Notchcast/Core"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
    # The real --jq filter over every fixture PR.
    'pr list '*)
        [ -z "${PRLIST_FAILS:-}" ] || { echo 'HTTP 502' >&2; exit 1; }
        base=$*
        base=${base#*--base }
        [[ "$*" == *' --base '* ]] || base=
        jq -s --arg base "${base%% *}" 'map(select(.state == "OPEN" and ($base == "" or .baseRefName == $base)))' "$FIXTURE"/pr-*.json | jq -r "${*: -1}" ;;
    # Logs the base it leaves and whether origin still had that branch.
    'pr edit '*'--base main')
        was=$(jq -r .baseRefName "$FIXTURE/pr-$3.json")
        echo "$3 $was $(git -C "$FIXTURE/origin.git" for-each-ref "refs/heads/$was" | wc -l | tr -d ' ')" >> "$FIXTURE/retargeted"
        jq '.baseRefName = "main"' "$FIXTURE/pr-$3.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$3.json" ;;
    'pr comment '*)
        echo "$3 ${*: -1}" >> "$FIXTURE/comments"
        jq --arg body "${*: -1}" '.comments += [{body: $body}]' "$FIXTURE/pr-$3.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$3.json" ;;
    # Mixed events, the real --jq: only the last land label add, at ready-<pr> or creation, is a sign-off.
    *issues/*/timeline*)
        [ -z "${TIMELINE_FAILS:-}" ] || { echo 'HTTP 502' >&2; exit 1; }
        [ -z "${TIMELINE_EMPTY:-}" ] || exit 0
        pr=${2#*issues/}
        pr=${pr%%/*}
        at=$(cat "$FIXTURE/ready-$pr" 2>/dev/null || jq -r .createdAt "$FIXTURE/pr-$pr.json")
        jq -n --arg at "$at" '($at | fromdateiso8601) as $t | def ev($e; $l; $d): {event: $e, label: {name: $l}, created_at: ($t + $d | todateiso8601)};
            [ev("labeled"; "land"; -7200), ev("unlabeled"; "land"; -3600), ev("labeled"; "land"; 0),
             ev("labeled"; "other"; 600), ev("ready_for_review"; null; 900)]' | jq -r "${*: -1}" ;;
    'pr view '*'--json headRefOid'*) jq -r .headRefOid "$FIXTURE/pr-$3.json" ;;
    'pr view '*)
        [ "$3" != "${VIEW_FAILS:-}" ] || { echo 'HTTP 502' >&2; exit 1; }
        cat "$FIXTURE/pr-$3.json" ;;
    'pr close '*)
        echo "$3 ${*: -1}" >> "$FIXTURE/closed"
        jq '.state = "CLOSED"' "$FIXTURE/pr-$3.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$3.json" ;;
    # runs-<sha> and workflow-runs-<sha>: the head's raw check runs and workflow runs, through the real --jq.
    *actions/runs\?head_sha=*)
        sha=$*
        sha=${sha#*head_sha=}
        [ ! -e "$FIXTURE/workflow-runs-fail-${sha%%&*}" ] || { echo '{"message":"Server Error","status":"502"}'; exit 1; }
        jq -r "${*: -1}" "$FIXTURE/workflow-runs-${sha%%&*}" ;;
    *check-runs*)
        sha=$*
        sha=${sha#*commits/}
        [ ! -e "$FIXTURE/runs-fail-${sha%%/*}" ] || { echo '{"message":"Server Error","status":"502"}'; exit 1; }
        if [ -e "$FIXTURE/runs-${sha%%/*}" ]; then jq -r "${*: -1}" "$FIXTURE/runs-${sha%%/*}"
        elif grep -qxF "${sha%%/*}" "$FIXTURE/red" 2>/dev/null; then echo failure
        elif grep -qxF "${sha%%/*}" "$FIXTURE/green" 2>/dev/null; then echo success
        elif grep -qxF "${sha%%/*}" "$FIXTURE/skipped" 2>/dev/null; then echo skipped; else echo "${HEAD_CHECKS:-success}"; fi ;;
    'workflow run '*)
        [[ -z "${DISPATCH_FAILS:-}" || "$*" != *"--ref $DISPATCH_FAILS "* ]] || { echo 'HTTP 422' >&2; exit 1; }
        python3 -c 'import os; print(os.getsid(0))' > "$FIXTURE/sid"
        echo "$*" >> "$FIXTURE/dispatched" ;;
    # KILL_TRAIN: the train is stopped while it waits, and again while it scraps.
    # RUN_IDS: each branch has one unfinished run, 5; RUNLIST_FAILS names a branch whose listing fails.
    'run list '*databaseId,status*)
        [ -z "${KILL_TRAIN:-}" ] || kill -TERM "$(cat "$FIXTURE/train-pid")"
        branch=$*
        branch=${branch#*-b }
        [ "${branch%% *}" != "${RUNLIST_FAILS:-}" ] || { echo 'HTTP 502' >&2; exit 1; }
        [ -z "${RUN_IDS:-}" ] || echo 5 ;;
    'run cancel '*) echo "$*" >> "$FIXTURE/cancelled" ;;
    'run list '*headSha,url*)
        branch=$*
        branch=${branch#*-b }
        echo "https://fixture.invalid/red/${branch%% *}" ;;
    # A dispatched train run is red when its branch train/<a>-<b> names a PR in RED_PRS.
    'run list '*workflow_dispatch*)
        if [ -n "${KILL_TRAIN:-}" ]; then kill -TERM "$(cat "$FIXTURE/train-pid")"; echo pending; exit 0; fi
        # STOP_QUEUE: the first verdict stops the queue tick around the train; later ones are green.
        if [ -n "${STOP_QUEUE:-}" ] && [ ! -e "$FIXTURE/stopped" ]; then
            : > "$FIXTURE/stopped"; kill -TERM "$(cat "$FIXTURE/queue-pid")"; echo pending; exit 0
        fi
        branch=$*
        branch=${branch#*-b train/}
        # PENDING_TRAINS: trains still running; asked about one, the stub leaves $FIXTURE/waiting.
        if [[ " ${PENDING_TRAINS:-} " == *" ${branch%% *} "* ]]; then : > "$FIXTURE/waiting"; echo pending; exit 0; fi
        verdict=success
        for pr in ${RED_PRS:-}; do
            [[ "-${branch%% *}-" != *"-$pr-"* ]] || verdict=failure
        done
        echo "$verdict" ;;
    *statuses*) ;;
    # ISOLATED is "<toolchain>|<excused harnesses>": the isolated runner's record of the tree, run 8.
    *'artifacts?name=tested-tree-isolated-'*) if [ -n "${ISOLATED:-}" ]; then echo '{"artifacts":[{"workflow_run":{"id":8}}]}'; else echo '{"artifacts":[]}'; fi ;;
    *actions/runs/8*) printf '{"id":8,"name":"PR","path":".github/workflows/pr.yml","conclusion":"success","repository":{"id":5},"head_repository":{"id":5,"full_name":"%s"},"html_url":"https://fixture.invalid/runs/8"}\n' "$FORK_REPO" ;;
    'run download 8 '*)
        echo "${ISOLATED%%|*}" > "${*: -1}/toolchain"
        echo "${ISOLATED#*|}" > "${*: -1}/excused" ;;
    *actions/runners*) [ -n "${OFFLINE:-}" ] || echo "${MAC_RUNNER:-}" ;;
    'variable get NOTCHCAST_MAC_RUNNER'*) [ -n "${MAC_RUNNER:-}" ] && echo "$MAC_RUNNER" || { echo 'variable NOTCHCAST_MAC_RUNNER was not found' >&2; exit 1; } ;;
    *actions/artifacts*) if [ -n "${TESTED:-}" ]; then echo '{"artifacts":[{"workflow_run":{"id":7}}]}'; else echo '{"artifacts":[]}'; fi ;;
    *actions/runs/7*) printf '{"name":"PR","path":".github/workflows/pr.yml","conclusion":"success","repository":{"id":5},"head_repository":{"id":5,"full_name":"%s"},"html_url":"https://fixture.invalid/runs/7"}\n' "$FORK_REPO" ;;
    'variable get LANDING_HOLD'*) [ -s "$FIXTURE/hold" ] && cat "$FIXTURE/hold" || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; } ;;
    'variable set LANDING_HOLD'*) echo "${*: -1}" > "$FIXTURE/hold" ;;
    'variable delete LANDING_HOLD'*) rm -f "$FIXTURE/hold" ;;
    'run list '*) ;;
    'issue close '*) echo "$3 ${*: -1}" >> "$FIXTURE/issues-closed" ;;
    *) echo "gh stub: unexpected $*" >&2; exit 3 ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/swiftc"
chmod +x "$scratch/bin/gh" "$scratch/bin/swiftc"
cp "$root"/notchcast/{land.sh,train.sh,merge.sh,merge-words.py,local-build-status.sh,drift-gates.sh,sync-wait.sh,hold.sh,config.env,fork-point.sh,land-tooling.txt,ci.py,app-proof.py,app-proofs.json,queue.sh} "$seed/notchcast/"
for name in check-drift.py check-drift-test.py; do
    printf '#!/usr/bin/env python3\n' > "$seed/notchcast/$name"
done
# The fixture's own hosted-runner skip, so it never depends on the real list.
# form-input-test is in both lists: it passes in no VM, so no run proves it and land.sh refuses it.
echo 'CI_SKIP_TESTS="clipboard-text-test form-input-test"' >> "$seed/notchcast/config.env"
echo 'HOSTED_ONLY_TESTS="hosted-test form-input-test"' >> "$seed/notchcast/config.env"
echo 'LINUX_OK_TESTS="notchcast-core-test hosted-test"' >> "$seed/notchcast/config.env"
echo 'ISOLATED_TOOLCHAIN="fixture toolchain"' >> "$seed/notchcast/config.env"
unset RUNNER_ENVIRONMENT NOTCHCAST_ISOLATED_RUNNER
# A message naming FORBIDDEN is refused, as check-identity.py refuses a private name.
printf '#!/bin/sh\n[ "$1" != message ] || ! grep -q FORBIDDEN "$2"\n' > "$seed/notchcast/check-identity.sh"
printf '#!/bin/sh\n' > "$seed/notchcast/check-bundle-readme.sh"
# Selects core, and <name>-test for a changed src/<name>.txt, as changed-harnesses.sh does from harness inputs.
cat > "$seed/notchcast/changed-harnesses.sh" <<'STUB'
#!/bin/bash
# --linux <file>: every harness of the fixture is linux-ok, so no reason is written.
if [ "$1" = --linux ]; then : > "$2"; shift 2; fi
[ -z "${SELECT_FAILS:-}" ] || exit 1
echo notchcast-core-test
for path in $(git diff --name-only "$1" "$2" -- src); do
    name=$(basename "$path" .txt)-test
    [ ! -e "Tests/$name.swift" ] || echo "$name"
done
STUB
# One line per pass in $PASSES; a harness is red while every file its red-with line names exists,
# or, with a red-under-load: <n> line, while the pass runs at least n harnesses.
cat > "$seed/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
BIN="$TMPDIR/tinycast-harness-fixture"
[ ! -e "$FIXTURE/slow" ] || { echo $$ > "$FIXTURE/started"; sleep 20; }
mkdir -p "$BIN"
ran=
status=0
run() {
    local name=$1
    case " $NOTCHCAST_ONLY_TESTS " in *" $name "*) ;; *) return 0 ;; esac
    local file red=1 needs load
    needs=$(sed -n 's/^red-with: //p' "Tests/$name.swift")
    : > "$BIN/$name.log"
    ran="$ran${ran:+ }$name"
    [ -n "$needs" ] || red=0
    for file in $needs; do
        [ -e "$file" ] || red=0
    done
    load=$(sed -n 's/^red-under-load: //p' "Tests/$name.swift")
    [ -z "$load" ] || [ "$(wc -w <<< "$NOTCHCAST_ONLY_TESTS")" -lt "$load" ] || red=1
    [ "$red" -eq 0 ] || { : > "$BIN/$name.failed"; status=1; }
}
for file in Tests/*-test.swift; do
    run "$(basename "$file" .swift)"
done
echo "$ran" >> "$PASSES"
exit $status
STUB
chmod +x "$seed"/notchcast/*.sh "$seed/Scripts/run-tests.sh"
for name in notchcast-core b c clipboard-text hosted form-input; do
    echo '// fixture' > "$seed/Tests/$name-test.swift"
done
echo 'red-with: src/a.txt src/b.txt' > "$seed/Tests/a-test.swift"
echo 'red-with: src/e.txt' > "$seed/Tests/clipboard-text-test.swift"
echo 'red-with: src/d.txt' > "$seed/Tests/d-test.swift"
echo 'red-under-load: 2' > "$seed/Tests/load-test.swift"
echo 'red-under-load: 4' > "$seed/Tests/heavy-test.swift"
echo base > "$seed/src/shared.txt"
printf '%s merge=notchcast-words\n' notchcast/config.env notchcast/docs/addons.md > "$seed/.gitattributes"
mkdir "$seed/notchcast/docs"
echo '| Launcher | F1 One | F9 Nine |' > "$seed/notchcast/docs/addons.md"
: > "$seed/Tinycast/Features/Notchcast/Core/NotchcastFeature.swift"
export HOME="$scratch/home" PATH="$scratch/bin:$PATH" NOTCHCAST_LAND_TOOLS=test
# train.sh --queue's clock: every sign-off in the fixture is older than its settle time unless a test sets one.
export NOTCHCAST_NOW=$(jq -n '"2026-03-01T00:00:00Z" | fromdateiso8601')
# The fixture's harnesses are stubs, so every train here lands as on a Mac, which runs each one.
export NOTCHCAST_PLATFORM=Darwin
identify() { git config user.name "$MAINTAINER_NAME"; git config user.email "$MAINTAINER_EMAIL"; }
git init --quiet -b main "$seed"
cd "$seed"
identify
git add .
git commit --quiet -m 'Fixture seed'
# A fresh origin and checkout at the seed.
fixture() {
    cd "$scratch"
    rm -rf "$scratch/run"
    export FIXTURE="$scratch/run" PASSES="$scratch/run/passes"
    mkdir "$FIXTURE"
    git clone --quiet --bare "$seed" "$FIXTURE/origin.git"
    git clone --quiet "$FIXTURE/origin.git" "$FIXTURE/work"
    cd "$FIXTURE/work"
    identify
    git remote add upstream "$FIXTURE/origin.git"
    base=$(git rev-parse HEAD)
    : > "$PASSES"
}
# open_pr <number> <branch> <title> <path>...: a ready PR on origin whose head writes its title into each path, with
# the labels PR_LABELS names (a JSON array, none by default).
open_pr() {
    local number=$1 branch=$2 title=$3 path
    shift 3
    git switch --quiet -c "$branch" "$base"
    for path in "$@"; do
        echo "$title" > "$path"
    done
    git add "$@"
    git commit --quiet -m "$title"
    git push --quiet origin "$branch" "$branch:refs/pull/$number/head"
    jq -n --arg head "$(git rev-parse HEAD)" --arg branch "$branch" --arg title "$title" --argjson number "$number" \
        --argjson labels "${PR_LABELS:-[]}" \
        '{number: $number, createdAt: "2026-01-0\($number)T00:00:00Z", comments: [], state: "OPEN", isDraft: false, headRefOid: $head, headRefName: $branch, baseRefName: "main", isCrossRepository: false, title: $title, body: "", labels: $labels}' \
        > "$FIXTURE/pr-$number.json"
    git switch --quiet main
}
selection() { notchcast/changed-harnesses.sh "$base" "$1"; }
land() {
    status=0
    bash notchcast/land.sh "$@" > "$FIXTURE/output" 2>&1 || status=$?
}
fail() { cat "$FIXTURE/output"; echo "FAIL: $1"; exit 1; }
origin() { git -C "$FIXTURE/origin.git" "$@"; }
landed() { origin log --reverse --format=%s "$base..main" | paste -sd'|' -; }
pass() { sed -n "$1p" "$PASSES"; }
# racing land <args>: origin's main moves to its meanwhile branch under land.sh's first push to main.
racing() {
    mkdir "$FIXTURE/bin"
    cat > "$FIXTURE/bin/git" <<'STUB'
#!/bin/bash
if [ "$1" = push ] && [[ "$*" == *:refs/heads/main ]] && [ ! -e "$FIXTURE/moved" ]; then
    : > "$FIXTURE/moved"
    "$REAL_GIT" -C "$FIXTURE/origin.git" update-ref refs/heads/main refs/heads/meanwhile
fi
exec "$REAL_GIT" "$@"
STUB
    chmod +x "$FIXTURE/bin/git"
    REAL_GIT=$(command -v git) PATH="$FIXTURE/bin:$PATH" "$@"
}

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
jq --arg repo "$FORK_REPO" '.closingIssuesReferences = [{number: 41, url: "https://github.com/\($repo)/issues/41"}, {number: 7, url: "https://github.com/other/repo/issues/7"}]' \
    "$FIXTURE/pr-1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-1.json"
union=$( { selection pr-b; selection pr-c; } | sort -u | paste -sd' ' -)
[ "$union" = 'b-test c-test notchcast-core-test' ] || fail "fixture union is '$union'"
land 1 2
[ "$status" -eq 0 ] || fail 'a green 2-PR train did not land'
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || fail "train landed '$(landed)'"
[ -z "$(origin rev-list --merges "$base..main")" ] && [ "$(origin rev-parse main~2)" = "$base" ] || fail 'the chain is not one parent per PR from base'
[ "$(origin log --format='%an %ae %cn %ce' "$base..main" | sort -u)" = "$MAINTAINER_NAME $MAINTAINER_EMAIL $MAINTAINER_NAME $MAINTAINER_EMAIL" ] \
    || fail 'a squash is not the repo identity'
[ "$(origin ls-tree -r --name-only main -- src | paste -sd' ' -)" = 'src/b.txt src/c.txt src/shared.txt' ] || fail 'the landed tree lacks a PR'
[ "$(wc -l < "$PASSES")" -eq 1 ] && [ "$(pass 1)" = "$union" ] || fail "passes were '$(paste -sd'|' "$PASSES")', not one of '$union'"
grep -q "^1 Landed on main as $(origin rev-parse main~1) .* onto $base\.$" "$FIXTURE/closed" \
    && grep -q "^2 Landed on main as $(origin rev-parse main) .* onto $(origin rev-parse main~1)\.$" "$FIXTURE/closed" || fail 'close comments'
[ -z "$(origin for-each-ref refs/heads/pr-b refs/heads/pr-c)" ] || fail 'landed heads were not deleted'
[ "$(cat "$FIXTURE/issues-closed")" = "41 Landed on main as $(origin rev-parse main~1) by notchcast/land.sh (#1)." ] && grep -q '^closed issue #41$' "$FIXTURE/output" \
    || fail "landing closed issues '$(cat "$FIXTURE/issues-closed" 2>/dev/null)', not only this repository's #41 that #1 closes"
echo 'PASS: landing closes the issues of this repository that each PR says it closes'
[ ! -e "$FIXTURE/hold" ] || fail 'the train left its hold behind'
echo 'PASS: a 2-PR train lands one squash per PR after one harness pass over the union of their selections'

# #2 is stacked on #1's branch: GitHub would close it when that branch is deleted.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
base=pr-b open_pr 2 pr-c 'Add C' src/c.txt
jq '.baseRefName = "pr-b"' "$FIXTURE/pr-2.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-2.json"
open_pr 3 pr-d 'Add D' src/plain.txt
land 1 3
[ "$status" -eq 0 ] && grep -q '^retargeted #2 from pr-b to main$' "$FIXTURE/output" || fail 'landing #1 did not say it moved the PR stacked on its branch'
[ "$(cat "$FIXTURE/retargeted")" = '2 pr-b 1' ] && [ "$(jq -r '.state + " " + .baseRefName' "$FIXTURE/pr-2.json")" = 'OPEN main' ] \
    || fail 'the stacked PR was not moved to main before its base was deleted'
grep -q '^kept origin/pr-b: open PR #2 stands on it$' "$FIXTURE/output" && [ -n "$(origin for-each-ref refs/heads/pr-b)" ] \
    || fail 'the branch the stacked PR was cut from was deleted'
[ -z "$(origin for-each-ref refs/heads/pr-d)" ] || fail 'a plain landed PR kept its branch'
echo 'PASS: a PR stacked on a landed branch is moved to main and that branch stays; a plain landed branch is deleted'

fixture
open_pr 1 pr-one 'Add one' src/shared.txt
open_pr 2 pr-two 'Add two' src/shared.txt
open_pr 3 pr-c 'Add C' src/c.txt
land 1 2 3
[ "$status" -eq 0 ] && grep -q 'REFUSED: merge conflict: src/shared.txt' "$FIXTURE/output" && grep -q 'DROPPED #2' "$FIXTURE/output" \
    || fail 'the conflicting PR was not dropped with its reason'
[ "$(landed)" = 'Notchcast: Add one (#1)|Notchcast: Add C (#3)' ] || fail "conflict train landed '$(landed)'"
[ "$(wc -l < "$PASSES")" -eq 1 ] && [ "$(pass 1)" = 'c-test notchcast-core-test' ] || fail "passes were '$(paste -sd'|' "$PASSES")'"
! grep -q '^2 ' "$FIXTURE/closed" && [ -n "$(origin rev-parse --verify -q refs/heads/pr-two)" ] || fail 'the dropped PR was closed or lost its head'
echo 'PASS: a PR that conflicts with the train is dropped and the rest lands'

# a-test is red only on a tree with both src/a.txt and src/b.txt: green on #1 alone, red from #2 on.
fixture
open_pr 1 pr-a 'Add A' src/a.txt
open_pr 2 pr-b 'Add B' src/b.txt
open_pr 3 pr-c 'Add C' src/c.txt
land 1 2 3
[ "$status" -eq 0 ] && grep -q 'DROPPED #2: a-test failed' "$FIXTURE/output" || fail 'a red train did not drop its breaking PR'
[ "$(landed)" = 'Notchcast: Add A (#1)|Notchcast: Add C (#3)' ] || fail "red train landed '$(landed)'"
[ "$(paste -sd'|' "$PASSES")" = 'a-test b-test c-test notchcast-core-test|a-test|a-test|a-test|a-test c-test notchcast-core-test' ] \
    || fail "full, alone, bisect and final passes were '$(paste -sd'|' "$PASSES")'"
[ "$(origin ls-tree -r --name-only main -- src | paste -sd' ' -)" = 'src/a.txt src/c.txt src/shared.txt' ] || fail 'the landed tree is not #1 and #3'
! grep -q '^2 ' "$FIXTURE/closed" && [ "$(wc -l < "$FIXTURE/closed")" -eq 2 ] && [ -n "$(origin rev-parse --verify -q refs/heads/pr-b)" ] \
    || fail 'the breaking PR was closed or lost its head'
echo 'PASS: a red pass bisects on the failing harness, drops the breaking PR and lands the rest after their own green pass'

# The first push to main finds it moved to a commit made meanwhile: the chain is rebuilt on it and tested again.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
git switch --quiet -c meanwhile "$base"
echo moved > src/moved.txt
git add src/moved.txt
git commit --quiet -m 'Fixture: main moves'
git push --quiet origin meanwhile
git switch --quiet main
racing land 1 2
[ "$status" -eq 0 ] && grep -q 'merging again and rerunning harnesses' "$FIXTURE/output" || fail 'a train did not follow main'
[ "$(landed)" = 'Fixture: main moves|Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || fail "after main moved the train landed '$(landed)'"
[ "$(paste -sd'|' "$PASSES")" = 'b-test c-test notchcast-core-test|b-test c-test notchcast-core-test' ] || fail "passes were '$(paste -sd'|' "$PASSES")'"
grep -q "^1 .* onto $(origin rev-parse meanwhile)\.$" "$FIXTURE/closed" || fail 'the close comment names the old base'
echo 'PASS: main moving under a train rebuilds the chain on it and reruns the pass'

fixture
open_pr 1 pr-d 'Add D' src/d.txt
land 1
[ "$status" -eq 1 ] && grep -q '^REFUSED: d-test failed$' "$FIXTURE/output" && ! grep -q DROPPED "$FIXTURE/output" || fail 'a red single PR'
[ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ] || fail 'a refused PR left something behind'
echo 'PASS: a single red PR refuses as before and lands nothing'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-load 'Add load' src/load.txt
land 1 2
[ "$status" -eq 1 ] && grep -q '^REFUSED: load-test failed in the full pass but passes alone on the merged tree: a load-only flake' "$FIXTURE/output" \
    && ! grep -q -e DROPPED -e bisecting "$FIXTURE/output" || fail 'a load-only flake was blamed on a PR'
[ "$(paste -sd'|' "$PASSES")" = 'b-test load-test notchcast-core-test|load-test' ] || fail "passes were '$(paste -sd'|' "$PASSES")'"
[ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ] || fail 'a flaky train left something behind'
echo 'PASS: a harness red in the full pass but green alone on the merged tree refuses as a flake and drops nobody'

# a-test is really red from #2 on; heavy-test is red only in a pass of 4 or more harnesses.
fixture
open_pr 1 pr-a 'Add A' src/a.txt
open_pr 2 pr-b 'Add B' src/b.txt
open_pr 3 pr-heavy 'Add heavy' src/heavy.txt
land 1 2 3
[ "$status" -eq 0 ] && grep -q '^DROPPED #2: a-test failed;' "$FIXTURE/output" || fail 'a partial flake did not drop only the real breaker'
[ "$(landed)" = 'Notchcast: Add A (#1)|Notchcast: Add heavy (#3)' ] || fail "partial flake train landed '$(landed)'"
[ "$(paste -sd'|' "$PASSES")" = 'a-test b-test heavy-test notchcast-core-test|a-test heavy-test|a-test|a-test|a-test heavy-test notchcast-core-test' ] \
    || fail "passes were '$(paste -sd'|' "$PASSES")'"
echo 'PASS: a real red and a load-only red in one pass bisect only the real one'

# notchcast-core-test is red on main itself, so every PR's tree inherits it.
fixture
echo 'red-with: src/shared.txt' > Tests/notchcast-core-test.swift
git commit --quiet -am 'Fixture: main is red'
git push --quiet origin main
base=$(git rev-parse HEAD)
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
land 1 2 3
[ "$status" -eq 1 ] && [ "$(grep -c REFUSED "$FIXTURE/output")" -eq 1 ] && grep -q '^REFUSED: main is red: notchcast-core-test$' "$FIXTURE/output" \
    && ! grep -q DROPPED "$FIXTURE/output" || fail 'a red main did not refuse once without dropping a PR'
[ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ] || fail 'a red main left something behind'
echo 'PASS: a harness red on main refuses the train once and drops nobody'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
for args in '1 2 1' '1 1'; do
    land $args
    [ "$status" -eq 1 ] && grep -q '^REFUSED: PR named more than once: 1$' "$FIXTURE/output" || fail "land.sh $args was not refused"
    [ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -s "$PASSES" ] || fail "land.sh $args did something"
done
echo 'PASS: a PR named twice refuses the train before anything runs'

fixture
open_pr 1 pr-b 'Add B' src/b.txt src/clipboard-text.txt
TESTED=1 land 1
[ "$status" -eq 0 ] && grep -q 'https://fixture.invalid/runs/7 built and tested this tree' "$FIXTURE/output" || fail 'tested tree not reused'
[ "$(paste -sd'|' "$PASSES")" = clipboard-text-test ] || fail "with a tested tree the passes were '$(paste -sd'|' "$PASSES")'"
[ "$(landed)" = 'Notchcast: Add B (#1)' ] || fail "tested tree landed '$(landed)'"
echo 'PASS: a green PR build of the merged tree leaves only the harnesses its runner skips'

fixture
open_pr 1 pr-h 'Add H' src/hosted.txt
land 1
[ "$status" -eq 1 ] && grep -q '^REFUSED: hosted-only harnesses are selected and no hosted run tested this tree: hosted-test;' "$FIXTURE/output" \
    || fail 'a selected hosted-only harness without a hosted run was not refused by name'
[ "$(origin rev-parse main)" = "$base" ] && [ ! -s "$PASSES" ] || fail 'a refused hosted-only selection ran or landed something'
echo 'PASS: a selected hosted-only harness refuses the landing, by name, without a hosted run of the tree'
TESTED=1 land 1
[ "$status" -eq 0 ] && [ ! -s "$PASSES" ] && [ "$(landed)" = 'Notchcast: Add H (#1)' ] \
    || fail "with a hosted run of the tree the hosted-only PR ran '$(paste -sd'|' "$PASSES")' and landed '$(landed)'"
echo 'PASS: a hosted run of the tree lands it, and the hosted-only harness never runs here'

fixture
open_pr 1 pr-h 'Add H' src/hosted.txt
RUNNER_ENVIRONMENT=github-hosted land 1
[ "$status" -eq 0 ] && [ "$(paste -sd'|' "$PASSES")" = 'hosted-test notchcast-core-test' ] || fail "on a hosted runner the pass was '$(paste -sd'|' "$PASSES")'"
echo 'PASS: on a GitHub-hosted runner the landing pass runs the hosted-only harness itself'

fixture
open_pr 1 pr-h 'Add H' src/hosted.txt
for where in NOTHING=1 RUNNER_ENVIRONMENT=github-hosted; do
    export "$where"
    NOTCHCAST_PLATFORM=Linux land 1
    unset "${where%%=*}"
    [ "$status" -eq 1 ] && grep -q '^REFUSED: hosted-only harnesses are selected and no hosted run tested this tree: hosted-test;' "$FIXTURE/output" \
        && [ "$(origin rev-parse main)" = "$base" ] && [ ! -s "$PASSES" ] || fail "on Linux ($where) a linux-ok selection with a hosted-only harness was not refused by name"
done
echo 'PASS: on Linux a linux-ok selection with a hosted-only harness is refused by name, on any runner'
NOTCHCAST_PLATFORM=Linux TESTED=1 land 1
[ "$status" -eq 0 ] && [ ! -s "$PASSES" ] && [ "$(landed)" = 'Notchcast: Add H (#1)' ] \
    || fail "on Linux with a hosted run of the tree the hosted-only PR ran '$(paste -sd'|' "$PASSES")' and landed '$(landed)'"
echo 'PASS: on Linux a hosted run of the tree lands it, and the hosted-only harness never runs there'

# The isolated runner skips nothing, so its record proves the hosted-only harness and the hosted runner's skip too.
fixture
open_pr 1 pr-h 'Add H' src/hosted.txt src/b.txt src/clipboard-text.txt
ISOLATED='other toolchain|' land 1
[ "$status" -eq 3 ] && [ "$(origin rev-parse main)" = "$base" ] && [ ! -s "$PASSES" ] \
    && grep -q "^REFUSED: the isolated run https://fixture.invalid/runs/8 tested this tree with 'other toolchain', and landing expects 'fixture toolchain'" "$FIXTURE/output" \
    || fail 'an isolated run with another toolchain was not refused'
echo 'PASS: an isolated run of the tree with a toolchain landing does not expect is refused'
ISOLATED='fixture toolchain|hosted-test' land 1
[ "$status" -eq 3 ] && [ "$(origin rev-parse main)" = "$base" ] && [ ! -s "$PASSES" ] \
    && grep -q '^REFUSED: the isolated run https://fixture.invalid/runs/8 did not prove hosted-test ' "$FIXTURE/output" \
    || fail 'an isolated run that excused a selected hosted-only harness was not refused by name'
echo 'PASS: an isolated run that excused a selected hosted-only harness is refused by name'
ISOLATED='fixture toolchain|b-test other-test' land 1
[ "$status" -eq 0 ] && grep -q 'the isolated run https://fixture.invalid/runs/8 proved all of them but b-test$' "$FIXTURE/output" \
    && [ "$(paste -sd'|' "$PASSES")" = b-test ] && [ "$(landed)" = 'Notchcast: Add H (#1)' ] \
    || fail "with an isolated run that excused b-test the passes were '$(paste -sd'|' "$PASSES")' and '$(landed)' landed"
echo 'PASS: an isolated run of the tree lands it, and only a selected harness it excused runs here'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
held="2 $(($(date +%s) + 600))"
echo "$held" > "$FIXTURE/hold"
land 1 2
[ "$status" -eq 0 ] && grep -q 'landing is held for #2' "$FIXTURE/output" && [ "$(landed)" = 'Notchcast: Add C (#2)' ] \
    && [ "$(cat "$FIXTURE/hold")" = "$held" ] || fail "under a hold for #2 the train landed '$(landed)'"
echo 'PASS: under a hold for one of its PRs the train lands only that PR and leaves the hold'

# train.sh <pr>...: prints "GREEN <branch> <sha8> on main <base8>: notchcast/land.sh --train-run <sha> <prs>".
train() {
    status=0
    NOTCHCAST_TRAIN_POLL=0 bash notchcast/train.sh "$@" > "$FIXTURE/train-output" 2>&1 || status=$?
    train_sha=$(sed -n 's/^GREEN .*--train-run \([0-9a-f]*\) .*/\1/p' "$FIXTURE/train-output" | tail -1)
}
draft() { jq '.isDraft = true' "$FIXTURE/pr-$1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$1.json"; }
label() { jq '.labels += [{name: "land"}]' "$FIXTURE/pr-$1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$1.json"; }
unlabel() { jq '.labels = []' "$FIXTURE/pr-$1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$1.json"; }
untouched() { [ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ]; }

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
[ "$status" -eq 0 ] && [ -n "$train_sha" ] || { cat "$FIXTURE/train-output"; fail 'a green train did not report its run'; }
[ "$(origin rev-parse refs/heads/train/1-2)" = "$train_sha" ] && [ "$(origin rev-parse "$train_sha~2")" = "$base" ] \
    && [ "$(origin rev-parse "$train_sha^2")" = "$(jq -r .headRefOid "$FIXTURE/pr-2.json")" ] || fail 'train/1-2 is not main plus each head'
[ "$(grep -c -- '--ref train/1-2' "$FIXTURE/dispatched")" -eq 4 ] && [ "$(grep -c "base=$base" "$FIXTURE/dispatched")" -eq 3 ] \
    && [ "$(grep -c 'hosted=true' "$FIXTURE/dispatched")" -eq 2 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^workflow run proof.yml .*hosted=true' "$FIXTURE/dispatched" \
    || fail "dispatched '$(paste -sd'|' "$FIXTURE/dispatched")'"
echo "$train_sha" > "$FIXTURE/green"
draft 1
draft 2
label 1
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q '^REFUSED: draft #2 has no land label' "$FIXTURE/output" && untouched \
    || fail 'a draft without the land label landed on a green train run'
echo 'PASS: a draft without the land label is refused even under a green train run'
land 1
[ "$status" -eq 1 ] && grep -q '^REFUSED: PR must be open and ready; a draft lands only on a green train run' "$FIXTURE/output" && untouched \
    || fail 'a labelled draft landed without a train run'
echo 'PASS: a labelled draft without --train-run is refused as before'
label 2
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 0 ] && grep -q "train: ${train_sha:0:8} is green on main" "$FIXTURE/output" || fail 'a green train run did not cover its PRs'
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] && [ "$(origin rev-parse 'main^{tree}')" = "$(origin rev-parse "$train_sha^{tree}")" ] \
    || fail "the train run landed '$(landed)'"
[ -z "$(origin for-each-ref refs/heads/train/)" ] || fail 'the landed train branch was not deleted'
echo 'PASS: a green train run lands its labelled draft PRs, red on their own heads, as the exact tree it tested, and deletes its branch'

# A hold cuts a train run to one PR, which the run did not build alone: that PR lands on its own head checks.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
echo "2 $(($(date +%s) + 600))" > "$FIXTURE/hold"
land --train-run "$train_sha" 1 2
[ "$status" -eq 0 ] && grep -q 'landing is held for #2' "$FIXTURE/output" && [ "$(landed)" = 'Notchcast: Add C (#2)' ] \
    || fail "under a hold for #2 the train run landed '$(landed)'"
echo 'PASS: under a hold a train run lands only the held PR, on its own head checks'

# A train built on a running train's tip (NOTCHCAST_TRAIN_ONTO) is covered once that train has landed, not before.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1
first=$train_sha
NOTCHCAST_TRAIN_ONTO=$base train 2
[ "$status" -eq 1 ] && grep -q "^REFUSED: NOTCHCAST_TRAIN_ONTO ${base:0:8} is the tip of no train branch of origin" "$FIXTURE/train-output" \
    || fail 'a train was built on a commit that is no train tip'
NOTCHCAST_TRAIN_ONTO=$first train 2
[ "$status" -eq 0 ] && [ -n "$train_sha" ] && [ "$(origin rev-parse "$train_sha^1")" = "$first" ] \
    && grep -q -- "--ref train/2 .*base=$first" "$FIXTURE/dispatched" && grep -q "^GREEN train/2 .* on train tip ${first:0:8}:" "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; fail 'the second train was not built on the first train tip'; }
second=$train_sha
printf '%s\n' "$first" "$second" > "$FIXTURE/green"
HEAD_CHECKS=failure land --train-run "$second" 2
[ "$status" -eq 1 ] && grep -q "is built on ${first:0:8}, not current main" "$FIXTURE/output" && untouched \
    || fail 'a train built on another landed before that one'
HEAD_CHECKS=failure land --train-run "$first" 1
[ "$status" -eq 0 ] || fail 'the first train did not land'
HEAD_CHECKS=failure land --train-run "$second" 2
[ "$status" -eq 0 ] && [ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] \
    && [ "$(origin rev-parse 'main^{tree}')" = "$(origin rev-parse "$second^{tree}")" ] || fail "the train built on a train landed '$(landed)'"
echo 'PASS: a train built on a running train tip lands after that train, as the tree it tested, and never before'

# While the repository variable names a runner the train's Mac jobs, PR's and Proof's, go there, and land.sh judges that run's record.
fixture
open_pr 1 pr-h 'Add H' src/hosted.txt
MAC_RUNNER=fixture-mac NOTCHCAST_TRAIN_MAC=hosted train 1
[ "$status" -eq 0 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^workflow run proof.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^train: train/1 has its Mac jobs on the hosted runner$' "$FIXTURE/train-output" || fail 'NOTCHCAST_TRAIN_MAC=hosted did not keep the train hosted'
origin push --quiet . --delete train/1 2>/dev/null || origin update-ref -d refs/heads/train/1
rm "$FIXTURE/dispatched"
OFFLINE=1 MAC_RUNNER=fixture-mac train 1
[ "$status" -eq 0 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^workflow run proof.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^train: no runner labelled fixture-mac is online, so the Mac jobs are hosted$' "$FIXTURE/train-output" \
    || fail 'a train went to a named runner that is offline'
echo 'PASS: a train stays hosted while no runner with the named label is online'
origin push --quiet . --delete train/1 2>/dev/null || origin update-ref -d refs/heads/train/1
rm "$FIXTURE/dispatched"
MAC_RUNNER=fixture-mac train 1
[ "$status" -eq 0 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" && grep -q '^workflow run proof.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^train: it selects hosted-only harnesses (hosted-test), which land.sh trusts only from a hosted run' "$FIXTURE/train-output" \
    && grep -q '^train: train/1 has its Mac jobs on the hosted runner$' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a train that selects a hosted-only harness went to the named runner'; }
echo 'PASS: a train that selects a hosted-only harness runs hosted even while a named runner is online'
fixture
open_pr 1 pr-b 'Add B' src/b.txt
SELECT_FAILS=1 MAC_RUNNER=fixture-mac train 1
[ "$status" -eq 0 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" && grep -q '^workflow run proof.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q 'changed-harnesses.sh failed' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a train whose harness selection failed went to the named runner'; }
echo 'PASS: a train whose harness selection fails runs hosted'
# A PR that makes a harness hosted-only: the tip's list counts, not only the caller's checkout.
fixture
git switch --quiet -c pr-n "$base"
echo new > src/new.txt
echo '// fixture' > Tests/new-test.swift
echo 'HOSTED_ONLY_TESTS="new-test"' >> notchcast/config.env
git add src/new.txt Tests/new-test.swift notchcast/config.env
git commit --quiet -m 'Add N'
git push --quiet origin pr-n pr-n:refs/pull/1/head
jq -n --arg head "$(git rev-parse HEAD)" '{number: 1, createdAt: "2026-01-01T00:00:00Z", comments: [], state: "OPEN", isDraft: false, headRefOid: $head, headRefName: "pr-n", baseRefName: "main", isCrossRepository: false, title: "Add N", body: "Drift tooling: fixture adds a hosted-only harness", labels: []}' > "$FIXTURE/pr-1.json"
git switch --quiet main
MAC_RUNNER=fixture-mac train 1
[ "$status" -eq 0 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" && grep -q '^workflow run proof.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q 'hosted-only harnesses (new-test)' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a PR that adds a hosted-only harness went to the named runner'; }
echo "PASS: a harness the PR itself makes hosted-only sends the train hosted"
fixture
open_pr 1 pr-b 'Add B' src/b.txt
MAC_RUNNER=fixture-mac train 1
[ "$status" -eq 0 ] && [ -n "$train_sha" ] && [ "$(grep -c '^workflow run ' "$FIXTURE/dispatched")" -eq 4 ] && ! grep -q 'hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^train: train/1 has its Mac jobs on the isolated runner$' "$FIXTURE/train-output" || fail "with a runner named the train dispatched '$(paste -sd'|' "$FIXTURE/dispatched")'"
echo "$train_sha" > "$FIXTURE/green"
ISOLATED='other toolchain|' land --train-run "$train_sha" 1
[ "$status" -eq 3 ] && grep -q "^REFUSED: the isolated run .* tested this tree with 'other toolchain'" "$FIXTURE/output" && untouched \
    || fail 'a train whose isolated run has another toolchain landed'
ISOLATED='fixture toolchain|' land --train-run "$train_sha" 1
[ "$status" -eq 0 ] && [ ! -s "$PASSES" ] && [ "$(landed)" = 'Notchcast: Add B (#1)' ] || fail "a train proven by the isolated runner landed '$(landed)'"
echo 'PASS: a train goes to the named Mac runner unless told hosted, and lands on its isolated run only with the expected toolchain'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
land --train-run "$train_sha" 1 2 3
[ "$status" -eq 1 ] && grep -q "does not merge #3's head" "$FIXTURE/output" && grep -q '^REFUSED: train .*, so no build tested the merged tree: run notchcast/train.sh 1 2 3 again$' "$FIXTURE/output" && untouched \
    || fail 'a train run missing a PR head landed on its green heads'
echo 'PASS: a train run missing a PR head is refused though each head is green, since no build tested the merged tree'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
git switch --quiet pr-c
echo moved > src/c.txt
git commit --quiet -am 'Move C'
git push --quiet origin pr-c pr-c:refs/pull/2/head
jq --arg head "$(git rev-parse HEAD)" '.headRefOid = $head' "$FIXTURE/pr-2.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-2.json"
git switch --quiet main
land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "does not merge #2's head" "$FIXTURE/output" && grep -q '^REFUSED: train .*, so no build tested the merged tree: run notchcast/train.sh 1 2 again$' "$FIXTURE/output" && untouched \
    || fail 'a PR head moved after the train was not refused'
echo 'PASS: a PR head that moved after the train run is refused though each head is green'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
echo moved > src/moved.txt
git add src/moved.txt
git commit --quiet -m 'Fixture: main moves'
git push --quiet origin main
base=$(git rev-parse HEAD)
land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q 'not current main' "$FIXTURE/output" && grep -q '^REFUSED: train .*, so no build tested the merged tree: run notchcast/train.sh 1 2 again$' "$FIXTURE/output" && untouched \
    || fail 'a train run on a stale base was not refused'
echo 'PASS: a train run whose base is no longer main is refused though each head is green'

# Main moves after the train went green. ci.py tested-key leaves out Tinycast.xcodeproj/project.pbxproj and keeps
# the Raycast runtime. The commit subject is the same each time, so only the paths it touches can decide.
for moved in Tinycast.xcodeproj/project.pbxproj src/moved.txt 'Tinycast.xcodeproj/project.pbxproj src/moved.txt' Tinycast/Resources/RaycastRuntime.generated.js; do
    fixture
    open_pr 1 pr-b 'Add B' src/b.txt
    open_pr 2 pr-c 'Add C' src/c.txt
    train 1 2
    echo "$train_sha" > "$FIXTURE/green"
    for path in $moved; do
        mkdir -p "$(dirname "$path")"
        echo moved > "$path"
        git add "$path"
    done
    git commit --quiet -m 'Notchcast: generated files'
    git push --quiet origin main
    base=$(git rev-parse HEAD)
    land --train-run "$train_sha" 1 2
    if [ "$moved" = Tinycast.xcodeproj/project.pbxproj ]; then
        [ "$status" -eq 0 ] && grep -q 'only in generated files; the run still proves it' "$FIXTURE/output" \
            && [ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || fail 'a train run did not land after main moved only in generated files'
        [ "$(origin rev-parse main~2)" = "$base" ] && [ "$(origin show main:Tinycast.xcodeproj/project.pbxproj)" = moved ] \
            && [ "$(origin diff --no-renames --name-only "$train_sha" main)" = Tinycast.xcodeproj/project.pbxproj ] || fail 'the landing is not the tested tree on the moved main'
        [ ! -s "$PASSES" ] && [ -z "$(origin for-each-ref refs/heads/train/)" ] || fail 'the proven train ran harnesses again or kept its branch'
    else
        [ "$status" -eq 1 ] && grep -q 'not current main' "$FIXTURE/output" && grep -q '^REFUSED: train .*, so no build tested the merged tree: run notchcast/train.sh 1 2 again$' "$FIXTURE/output" && untouched \
            || fail "a train run was not refused after main moved in '$moved'"
    fi
done
echo 'PASS: main moving only in the generated project keeps a train run'"'"'s proof; a move that touches any other path, the Raycast runtime too, refuses'

# Main moves under the covered train's push, to a commit made before the train ran.
for moved in Tinycast.xcodeproj/project.pbxproj src/moved.txt; do
    fixture
    open_pr 1 pr-b 'Add B' src/b.txt
    open_pr 2 pr-c 'Add C' src/c.txt
    git switch --quiet -c meanwhile "$base"
    mkdir -p "$(dirname "$moved")"
    echo moved > "$moved"
    git add "$moved"
    git commit --quiet -m 'Fixture: main moves'
    git push --quiet origin meanwhile
    git switch --quiet main
    train 1 2
    echo "$train_sha" > "$FIXTURE/green"
    HEAD_CHECKS=failure racing land --train-run "$train_sha" 1 2
    if [ "$moved" = Tinycast.xcodeproj/project.pbxproj ]; then
        [ "$status" -eq 0 ] && grep -q 'only in generated files; merging again without rerunning harnesses' "$FIXTURE/output" \
            && [ "$(landed)" = 'Fixture: main moves|Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || fail 'a covered train did not land after main moved only in generated files under its push'
        [ ! -s "$PASSES" ] && [ "$(origin diff --no-renames --name-only "$train_sha" main)" = "$moved" ] \
            || fail 'the raced landing ran harnesses or is not the tested tree on the moved main'
    else
        base=$(origin rev-parse meanwhile)
        [ "$status" -eq 1 ] && grep -q "^REFUSED: main moved past train ${train_sha:0:8}'s base" "$FIXTURE/output" && untouched && [ ! -s "$PASSES" ] \
            || fail 'a covered train was not refused after main moved in another path under its push'
    fi
done
echo 'PASS: main moving under a covered train'"'"'s push lands it untested again when only the generated project moved, and refuses on any other path'

# A green run whose tree is not the merge of its parents: the heads and the base match, the tree does not.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
git fetch --quiet origin train/1-2
git switch --quiet --detach "$train_sha"
echo extra > src/extra.txt
git add src/extra.txt
git commit --quiet --amend --no-edit
train_sha=$(git rev-parse HEAD)
git push --quiet origin HEAD:refs/heads/train/extra
git switch --quiet main
echo "$train_sha" > "$FIXTURE/green"
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "^REFUSED: the merged tree is not the tree train ${train_sha:0:8} tested" "$FIXTURE/output" && untouched \
    || fail 'a train run whose tree is not the merged tree was not refused'
echo 'PASS: a train run that tested another tree than the one land.sh merges is refused'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "${train_sha:0:8} has build failure" "$FIXTURE/output" && untouched || fail 'a red train run was not refused'
echo 'PASS: a red train run covers nothing and lands nothing'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
RED_PRS=2 train 1 2 3
[ "$status" -eq 1 ] && grep -q '^RED train/1-2-3: splitting into 1 2 | 3$' "$FIXTURE/train-output" \
    && grep -q '^RED train/1-2: splitting into 1 | 2$' "$FIXTURE/train-output" && grep -q '^RED #2 alone' "$FIXTURE/train-output" \
    && grep -q '^GREEN train/3 .* --train-run [0-9a-f]* 3$' "$FIXTURE/train-output" && grep -q '^GREEN train/1 .* --train-run [0-9a-f]* 1$' "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; fail 'a red train did not bisect to its red PR'; }
[ "$(origin for-each-ref --format='%(refname:lstrip=2)' refs/heads/train/ | paste -sd' ' -)" = 'train/1 train/3' ] || fail 'red train branches were kept'
untouched || fail 'train.sh touched main'
echo 'PASS: a red train splits in halves onto new trains down to the red PR, keeps only green train branches and lands nothing'

fixture
open_pr 1 pr-one 'Add one' src/shared.txt
open_pr 2 pr-two 'Add two' src/shared.txt
git merge --quiet --ff-only pr-one
git push --quiet origin main
base=$(git rev-parse HEAD)
train 2
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: conflicts with main in src/shared.txt: it waits for one merge round, which the landing owner starts when this PR is next to land; nobody merges main into it before that$' "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; fail 'a train of one PR that conflicts with main was not dropped'; }
[ -z "$(origin for-each-ref refs/heads/train/)" ] && [ ! -e "$FIXTURE/dispatched" ] && untouched || fail 'a train with no PR left pushed or dispatched'
echo 'PASS: a train whose every merge is refused pushes no branch and dispatches nothing'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
draft 1
train 1 2
[ "$status" -eq 1 ] && grep -q "^DROPPED #1: dropped from the landing batch: draft #1 has no land label, the lead's sign-off to land it$" "$FIXTURE/train-output" \
    && grep -q '^GREEN train/2 ' "$FIXTURE/train-output" && ! grep -q -- '--ref train/1-2' "$FIXTURE/dispatched" \
    || { cat "$FIXTURE/train-output"; fail 'an unlabelled draft reached the train run that land.sh would then refuse whole'; }
echo 'PASS: an unlabelled draft is dropped before the train is pushed, so it never voids a green run at landing'

# #2 merged #1's branch into its own and went on in #1's file, so its head holds #1's commit; #3 shares nothing.
tangled() {
    fixture
    open_pr 1 pr-b 'Add B' src/b.txt
    open_pr 2 pr-c 'Add C' src/c.txt
    open_pr 3 pr-one 'Add one' src/one.txt
    git switch --quiet pr-c
    git merge --quiet --no-edit pr-b
    echo 'C on B' > src/b.txt
    git commit --quiet -am 'C on B'
    repush 2 pr-c
}
# repush <number> <branch>: the PR's head becomes the checked-out commit.
repush() {
    git push --quiet origin "$2" "$2:refs/pull/$1/head"
    jq --arg head "$(git rev-parse HEAD)" '.headRefOid = $head' "$FIXTURE/pr-$1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$1.json"
    git switch --quiet main
}
# train.sh $1 is refused, saying #2 holds #1, before anything is pushed, dispatched or commented.
refused_holder() {
    train $1
    [ "$status" -eq 1 ] && grep -q '^REFUSED: #2 contains commits of #1, .* so #2 can conflict with main once #1 lands\. Land #1 first; then #2 gets one merge round, which the landing owner starts when it is next to land\.$' "$FIXTURE/train-output" \
        || { cat "$FIXTURE/train-output"; echo "FAIL: train.sh $1, where #2 holds #1's commits$2, was not refused naming #2 as the holder"; exit 1; }
    [ -z "$(origin for-each-ref refs/heads/train/)" ] && [ ! -e "$FIXTURE/dispatched" ] && [ ! -e "$FIXTURE/comments" ] && untouched \
        || { echo "FAIL: the refused train.sh $1 pushed, dispatched or commented"; exit 1; }
}
tangled
for args in '1 2' '2 1' '2 1 3'; do
    refused_holder "$args" ''
done
train 1 3
[ "$status" -eq 0 ] && grep -q '^GREEN train/1-3 ' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; echo 'FAIL: an unrelated pair beside the tangled PR did not run'; exit 1; }
echo "PASS: a train in which one PR holds another's commits is refused before any dispatch, naming both; an unrelated pair runs"

tangled
git switch --quiet pr-b
echo 'B again' > src/b.txt
git commit --quiet -am 'B again'
repush 1 pr-b
for args in '1 2' '2 1'; do
    refused_holder "$args" ', and #1 moved on since'
done
echo 'PASS: the PR that merged the other is named the holder in either order, also after the other moved on'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
for number in 1 2; do
    git switch --quiet "$(jq -r .headRefName "$FIXTURE/pr-$number.json")"
    git merge --quiet --no-edit pr-one
    repush "$number" "$(git branch --show-current)"
done
train 1 2
[ "$status" -eq 0 ] && grep -q '^GREEN train/1-2 ' "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; echo 'FAIL: two PRs that merged the same unlanded branch were not run together'; exit 1; }
train 3 1
[ "$status" -eq 1 ] && grep -q '^REFUSED: #1 contains commits of #3, ' "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; echo 'FAIL: a PR in a train with the branch it merged was not refused'; exit 1; }
echo 'PASS: two PRs that merged the same unlanded branch hold nothing of each other and run; either with that branch is refused'

# --queue: picks the batch itself and lands what is green; LAND_BATCH_SIZE is appended to the checkout's config.env.
queue() {
    status=0
    NOTCHCAST_TRAIN_POLL=0 bash notchcast/train.sh --queue > "$FIXTURE/train-output" 2>&1 || status=$?
}
queue_fail() { cat "$FIXTURE/train-output"; echo "FAIL: $1"; exit 1; }
# From here on each fixture PR is signed off: labelled land, the only thing the queue takes.
export PR_LABELS='[{"name": "land"}]'

# #2 was labelled land before #1 was opened; #3 is red on its head, #4 ready but unlabelled, #5 past the batch size.
fixture
echo LAND_BATCH_SIZE=2 >> notchcast/config.env
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
open_pr 4 pr-d 'Add D' src/d.txt
open_pr 5 pr-a 'Add A' src/a.txt
echo 2025-12-01T00:00:00Z > "$FIXTURE/ready-2"
jq -r .headRefOid "$FIXTURE/pr-3.json" > "$FIXTURE/red"
unlabel 4
queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 2 1$' "$FIXTURE/train-output" && grep -q '^LANDED #2 1$' "$FIXTURE/train-output" \
    && grep -q '^open PRs: 5/25$' "$FIXTURE/train-output" \
    || queue_fail 'a green batch did not land'
[ "$(landed)" = 'Notchcast: Add C (#2)|Notchcast: Add B (#1)' ] || queue_fail "the green batch landed '$(landed)'"
[ "$(grep -c -- '--ref train/2-1\( \|$\)' "$FIXTURE/dispatched")" -eq 4 ] && [ "$(wc -l < "$FIXTURE/dispatched")" -eq 4 ] \
    || queue_fail "the green batch dispatched '$(paste -sd'|' "$FIXTURE/dispatched")'"
[ "$(cut -d' ' -f1 "$FIXTURE/closed" | paste -sd' ' -)" = '2 1' ] && [ -z "$(origin for-each-ref refs/heads/train/)" ] && [ ! -e "$FIXTURE/comments" ] \
    || queue_fail 'the green batch did not close exactly its PRs and delete its branch'
echo 'PASS: --queue stacks the oldest signed-off green PRs up to the batch size, runs them once and lands one commit per PR'

# Only land is a sign-off (#1203): (a) #4 ready, unlabelled; (b) #2 a labelled draft whose build is skipped;
# (c) #1 ready, labelled, green; (d) #3 ready, labelled, red. A ready PR's own skipped build still holds it.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
open_pr 4 pr-d 'Add D' src/d.txt
open_pr 5 pr-a 'Add A' src/a.txt
unlabel 4
draft 2
jq -r .headRefOid "$FIXTURE/pr-2.json" "$FIXTURE/pr-5.json" > "$FIXTURE/skipped"
jq -r .headRefOid "$FIXTURE/pr-3.json" > "$FIXTURE/red"
queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 1 2$' "$FIXTURE/train-output" && grep -q '^LANDED #1 2$' "$FIXTURE/train-output" \
    && grep -q "^queue: #3 waits, build is failure on " "$FIXTURE/train-output" \
    && grep -q "^queue: #5 waits, build is skipped on " "$FIXTURE/train-output" && ! grep -q '#4' "$FIXTURE/train-output" \
    || queue_fail 'the queue took a PR without land, or held a labelled draft whose build was skipped'
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || queue_fail "the land-only batch landed '$(landed)'"
echo 'PASS: --queue takes only PRs labelled land: a green ready one and a draft with a skipped build ride, red or unlabelled wait'

# #1304: a dispatched build the push's pull_request run cancelled. (a) #1 a labelled draft: that run skipped build, its
# skip timed before the cancel; (b) #2 cancelled alone; (c) #3 the cancelling run still runs; (d) #4 it went red;
# (e) #5 the cancelled run is re-running under its own check suite; (f) #6 the runs listing errors.
fixture
for n in 1 2 3 4 5 6; do open_pr "$n" "pr-$n" "Add $n" "src/$n.txt"; done
draft 1
build_run() { printf '{"app":{"slug":"github-actions"},"check_suite":{"id":%s},"started_at":"2026-11-21T01:15:%s","status":"completed","conclusion":"%s"}' "$@"; }
workflow_run() { printf '{"workflow_id":7,"check_suite_id":%s,"status":"%s"}' "$@"; }
superseded() {
    local head
    head=$(jq -r .headRefOid "$FIXTURE/pr-$1.json")
    echo "{\"check_runs\":[$2]}" > "$FIXTURE/runs-$head"
    echo "{\"workflow_runs\":[$3]}" > "$FIXTURE/workflow-runs-$head"
}
superseded 1 "$(build_run 20 26Z cancelled),$(build_run 21 25Z skipped)" "$(workflow_run 20 completed),$(workflow_run 21 completed)"
superseded 2 "$(build_run 30 26Z cancelled)" "$(workflow_run 30 completed)"
superseded 3 "$(build_run 40 26Z cancelled)" "$(workflow_run 40 completed),$(workflow_run 41 in_progress)"
superseded 4 "$(build_run 50 26Z cancelled),$(build_run 51 59Z failure)" "$(workflow_run 50 completed),$(workflow_run 51 completed)"
superseded 5 "$(build_run 60 26Z cancelled)" "$(workflow_run 60 in_progress)"
superseded 6 "$(build_run 70 26Z cancelled)" "$(workflow_run 70 completed),$(workflow_run 71 in_progress)"
touch "$FIXTURE/workflow-runs-fail-$(jq -r .headRefOid "$FIXTURE/pr-6.json")"
queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 1$' "$FIXTURE/train-output" && grep -q '^LANDED #1$' "$FIXTURE/train-output" \
    && grep -q '^queue: #2 waits, build is cancelled on ' "$FIXTURE/train-output" \
    && grep -q '^queue: #3 waits, build is pending on ' "$FIXTURE/train-output" \
    && grep -q '^queue: #4 waits, build is failure on ' "$FIXTURE/train-output" \
    && grep -q '^queue: #5 waits, build is pending on ' "$FIXTURE/train-output" \
    && grep -q '^queue: #6 waits, build is cancelled on ' "$FIXTURE/train-output" \
    || queue_fail 'a superseded cancelled build held a PR, or a lone cancel, a running, re-running, red or unlisted build let one through'
echo 'PASS: --queue reads a cancelled build by the run that superseded it: skipped rides a draft, running or re-running waits pending, red waits, a listing error reads cancelled'

# The check runs call fails: the queue stops non-zero, never waits on a blank or garbled verdict.
fixture
open_pr 1 pr-1 'Add 1' src/1.txt
touch "$FIXTURE/runs-fail-$(jq -r .headRefOid "$FIXTURE/pr-1.json")"
queue
[ "$status" -ne 0 ] && ! grep -q 'waits, build is' "$FIXTURE/train-output" && ! grep -q '^LANDED' "$FIXTURE/train-output" \
    || queue_fail "a failed check runs call left the queue going (exit $status)"
echo 'PASS: --queue stops non-zero when the check runs call fails'

# A hold for #2 cuts the green batch 1 2 to #2 in land.sh: the queue says only #2 landed and #1 is held (#1119).
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
held="2 $(($(date +%s) + 600))"
echo "$held" > "$FIXTURE/hold"
queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 1 2$' "$FIXTURE/train-output" && grep -q '^LANDED #2$' "$FIXTURE/train-output" \
    && grep -q '^HELD #1: landing is held for #2, ' "$FIXTURE/train-output" && ! grep -q '^LANDED #1' "$FIXTURE/train-output" \
    || queue_fail 'under a hold the queue did not say which PR landed and which were held'
[ "$(landed)" = 'Notchcast: Add C (#2)' ] && [ "$(cat "$FIXTURE/hold")" = "$held" ] || queue_fail "under a hold for #2 the queue landed '$(landed)'"
echo 'PASS: under a hold for one PR of the batch, --queue prints that only it landed and the rest are held'

# Unprovable: a harness in both lists passes in no VM, so land.sh refuses for good a PR that selects one.
head_of() { jq -r .headRefOid "$FIXTURE/pr-$1.json"; }
refused() { echo "REFUSED: no run proves $1: it is in both HOSTED_ONLY_TESTS and CI_SKIP_TESTS (notchcast/config.env, main's or the PR's); make it pass on a hosted VM and take it out of CI_SKIP_TESTS"; }
for platform in Darwin Linux; do
    fixture
    open_pr 1 pr-f 'Add F' src/form-input.txt src/hosted.txt
    NOTCHCAST_PLATFORM=$platform TESTED=1 land 1
    [ "$status" -eq 3 ] && grep -qxF "$(refused form-input-test)" "$FIXTURE/output" \
        && ! grep -q -e SKIPPED -e ROUTED "$FIXTURE/output" && untouched && [ ! -s "$PASSES" ] \
        || fail "on $platform land.sh did not refuse for good a harness no run proves"
done
echo 'PASS: land.sh refuses for good a harness in both lists, whatever runs tested the tree, on a Mac and on Linux'
# list_change <title> <line> <path>...: PR #1 appends <line> to config.env (the last line sets a list) and writes each path.
list_change() {
    local title=$1 line=$2
    shift 2
    git switch --quiet -c pr-l "$base"
    for path in "$@"; do echo "$title" > "$path"; done
    echo "$line" >> notchcast/config.env
    git add "$@" notchcast/config.env
    git commit --quiet -m "$title"
    git push --quiet origin pr-l pr-l:refs/pull/1/head
    jq -n --arg head "$(git rev-parse HEAD)" --arg title "$title" '{number: 1, createdAt: "2026-01-01T00:00:00Z", comments: [], state: "OPEN", isDraft: false, headRefOid: $head, headRefName: "pr-l", baseRefName: "main", isCrossRepository: false, title: $title, body: "Drift tooling: fixture changes a harness list", labels: []}' > "$FIXTURE/pr-1.json"
    git switch --quiet main
}
# Main's lists: a PR that takes the harness out of one list at its tip still selects one unprovable on main.
fixture
list_change 'Add F' 'CI_SKIP_TESTS="clipboard-text-test"' src/form-input.txt
TESTED=1 land 1
[ "$status" -eq 3 ] && grep -qxF "$(refused form-input-test)" "$FIXTURE/output" && untouched \
    || fail 'a harness unprovable on main landed'
# The PR's lists: a new harness it puts in both lists had its own hosted run skip it.
fixture
list_change 'Add X' 'CI_SKIP_TESTS="clipboard-text-test form-input-test x-test"' src/x.txt Tests/x-test.swift
git switch --quiet pr-l
echo 'HOSTED_ONLY_TESTS="hosted-test form-input-test x-test"' >> notchcast/config.env
git commit --quiet -am 'Add X hosted-only'
git push --quiet origin pr-l pr-l:refs/pull/1/head
jq --arg head "$(git rev-parse HEAD)" '.headRefOid = $head' "$FIXTURE/pr-1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-1.json"
git switch --quiet main
TESTED=1 land 1
[ "$status" -eq 3 ] && grep -qxF "$(refused x-test)" "$FIXTURE/output" && untouched \
    || fail 'a harness the PR makes unprovable landed'
echo "PASS: land.sh takes the unprovable set from main's lists and the PR's"
# A green train land.sh refuses for good (exit 3) is recorded at its heads, with the runner it ran on and main's
# config.env. Both such refusals judge an isolated record, so the next tick trains the batch hosted; only a batch
# refused on a hosted train is left out, until a head or config.env changes. Here the isolated record has a toolchain
# landing does not expect.
refused_once() {
    fixture
    open_pr 1 pr-b 'Add B' src/b.txt
    mkdir -p "$HOME/.config/notchcast"
    echo 'notchcast_notify() { cat >> "$FIXTURE/notified"; }' > "$HOME/.config/notchcast/private.env"
    head1=$(head_of 1)
    key=$(git hash-object notchcast/config.env)
    ISOLATED='other toolchain|' MAC_RUNNER=fixture-mac queue
    [ "$status" -eq 1 ] && grep -q '^REFUSED: the isolated run https://fixture.invalid/runs/8 tested this tree with .other toolchain.' "$FIXTURE/train-output" \
        && grep -qxF 'REFUSED FOR GOOD #1: its train branch train/1 stays; the queue trains these PRs hosted next, the run that can change that verdict' "$FIXTURE/train-output" \
        && [ "$(wc -l < "$FIXTURE/dispatched")" -eq 4 ] && ! grep -q 'hosted=true' "$FIXTURE/dispatched" && untouched \
        || queue_fail 'a green train refused for good on the isolated runner was not recorded'
    [ "$(wc -l < "$FIXTURE/comments")" -eq 1 ] && grep -q "^1 Refused for good at its head $head1: land.sh refused the green train train/1 (#1) on the isolated runner: the isolated run " "$FIXTURE/comments" \
        && [ "$(wc -l < "$FIXTURE/notified")" -eq 1 ] && grep -q '^Notchcast: land.sh refused the green train train/1 (#1) for good on the isolated runner: ' "$FIXTURE/notified" \
        || queue_fail "the refusal was told as '$(cat "$FIXTURE/comments")' and '$(cat "$FIXTURE/notified" 2>/dev/null)'"
    [ "$(cat .git/notchcast-refused)" = "isolated $key 1@$head1" ] || queue_fail "the record is '$(cat .git/notchcast-refused 2>/dev/null)'"
}
# hosted_tick <what>: the tick after the refusal trains the batch hosted and lands it.
hosted_tick() {
    [ "$status" -eq 0 ] && grep -q '^LANDED #1$' "$FIXTURE/train-output" && [ "$(wc -l < "$FIXTURE/dispatched")" -eq 8 ] \
        && [ "$(grep -c 'hosted=true' "$FIXTURE/dispatched")" -eq 2 ] && ! grep -q 'left out' "$FIXTURE/train-output" \
        && [ "$(landed)" = 'Notchcast: Add B (#1)' ] || queue_fail "$1 did not dispatch the refused batch and land it"
}
refused_once
ISOLATED='fixture toolchain|' MAC_RUNNER=fixture-mac queue
grep -q '^queue: #1 train hosted: land.sh refused them for good on the isolated runner at these heads$' "$FIXTURE/train-output" \
    && grep -q '^train: land.sh refused a PR of it for good on the isolated runner at its head, so its Mac jobs are hosted$' "$FIXTURE/train-output" \
    || queue_fail 'the tick after a refusal on the isolated runner did not train it hosted'
hosted_tick 'a tick with the isolated runner back on the expected toolchain'
refused_once
NOTCHCAST_TRAIN_MAC=hosted TESTED=1 queue
hosted_tick 'a tick with NOTCHCAST_TRAIN_MAC=hosted'
echo 'PASS: a batch refused for good on the isolated runner is told once, and the next tick trains it hosted and lands it'
# A hosted train of it refused for good again is left out at the same heads and config.
refused_once
for tick in 2 3; do
    ISOLATED='other toolchain|' MAC_RUNNER=fixture-mac queue
done
[ "$status" -eq 0 ] && grep -q '^queue: #1 left out: land.sh refused them for good at these heads$' "$FIXTURE/train-output" \
    && [ "$(wc -l < "$FIXTURE/dispatched")" -eq 8 ] && [ "$(grep -c 'hosted=true' "$FIXTURE/dispatched")" -eq 2 ] \
    && [ "$(wc -l < "$FIXTURE/comments")" -eq 2 ] && [ "$(wc -l < "$FIXTURE/notified")" -eq 2 ] \
    && grep -q '^Notchcast: land.sh refused the green train train/1 (#1) for good on the hosted runner: .*; the queue leaves these PRs out until one has a new head or config.env changes$' "$FIXTURE/notified" \
    || queue_fail 'a batch refused for good on a hosted train was dispatched, commented or notified again'
echo 'PASS: a batch refused for good on a hosted train too is left out at the same heads, told once each time'
# Another config.env forgets the record.
sed -i.bak "s/ $key / 0000 /" .git/notchcast-refused
ISOLATED='fixture toolchain|' MAC_RUNNER=fixture-mac queue
[ "$status" -eq 0 ] && ! grep -q -e 'left out' -e 'train hosted' "$FIXTURE/train-output" && grep -q '^LANDED #1$' "$FIXTURE/train-output" \
    && [ "$(wc -l < "$FIXTURE/dispatched")" -eq 12 ] && [ "$(grep -c 'hosted=true' "$FIXTURE/dispatched")" -eq 2 ] && [ ! -s .git/notchcast-refused ] \
    || queue_fail 'a record of another config.env was applied'
echo 'PASS: a record made under another config.env is forgotten'
# A new head forgets it too.
refused_once
for tick in 2 3; do
    ISOLATED='other toolchain|' MAC_RUNNER=fixture-mac queue
done
git switch --quiet pr-b
echo 'Add B again' > src/b.txt
git commit --quiet -am 'Add B again'
repush 1 pr-b
ISOLATED='fixture toolchain|' MAC_RUNNER=fixture-mac queue
[ "$status" -eq 0 ] && grep -q '^train: train/1 is left from an earlier run; scrapping it$' "$FIXTURE/train-output" && grep -q '^LANDED #1$' "$FIXTURE/train-output" \
    && [ "$(wc -l < "$FIXTURE/dispatched")" -eq 12 ] && [ "$(landed)" = 'Notchcast: Add B (#1)' ] && [ ! -s .git/notchcast-refused ] \
    || queue_fail 'a new head on a refused PR did not clear its record and dispatch it again'
rm "$HOME/.config/notchcast/private.env"
echo 'PASS: a new head on a PR of a refused batch clears the record, and the next tick dispatches it again'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
RED_PRS=2 queue
[ "$status" -eq 1 ] && grep -q '^CULPRIT #2 https://fixture.invalid/red/train/2$' "$FIXTURE/train-output" || queue_fail 'a red batch did not report its culprit'
[ "$(grep -c '^LANDED' "$FIXTURE/train-output")" -eq 2 ] && [ "$(landed)" = 'Notchcast: Add one (#3)|Notchcast: Add B (#1)' ] \
    || queue_fail "the red batch landed '$(landed)'"
[ "$(cat "$FIXTURE/comments")" = "2 Red alone on main $(origin rev-parse --short=8 main~1) in the landing batch at head $(jq -r .headRefOid "$FIXTURE/pr-2.json"): https://fixture.invalid/red/train/2" ] \
    || queue_fail "the culprit comment was '$(cat "$FIXTURE/comments")'"
! grep -q '^2 ' "$FIXTURE/closed" && [ -z "$(origin for-each-ref refs/heads/train/)" ] || queue_fail 'the culprit was closed or a train branch was left'
base=$(origin rev-parse main)
queue
[ "$status" -eq 0 ] && grep -q '^queue: no open PR' "$FIXTURE/train-output" && [ "$(origin rev-parse main)" = "$base" ] \
    || queue_fail 'the culprit was picked again on the same head'
echo 'PASS: a red batch splits in halves, lands each green half on the main the one before it left, and reports the culprit once'

fixture
open_pr 1 pr-one 'Add one' src/shared.txt
open_pr 2 pr-two 'Add two' src/shared.txt
open_pr 3 pr-c 'Add C' src/c.txt
queue
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: conflicts with #1 in the landing batch in src/shared.txt: it rides a later train, after #1 lands; nobody merges main into it$' "$FIXTURE/train-output" \
    && [ "$(cat "$FIXTURE/comments")" = "2 Left out of the landing batch at its head $(jq -r .headRefOid "$FIXTURE/pr-2.json"): conflicts with #1 in the landing batch in src/shared.txt: it rides a later train, after #1 lands; nobody merges main into it" ] \
    || queue_fail 'the later conflicting PR was not dropped and told'
[ "$(landed)" = 'Notchcast: Add one (#1)|Notchcast: Add C (#3)' ] && [ "$(grep -c -- '--ref train/1-3\( \|$\)' "$FIXTURE/dispatched")" -eq 4 ] \
    && ! grep -q '^2 ' "$FIXTURE/closed" || queue_fail "the conflict batch landed '$(landed)'"
queue
[ "$status" -eq 1 ] && grep -q '^queue: batch 2$' "$FIXTURE/train-output" && grep -q '^DROPPED #2: conflicts with main in src/shared.txt: ' "$FIXTURE/train-output" \
    || queue_fail 'a PR left out behind a PR that has landed was not taken again'
echo 'PASS: a PR that conflicts with an earlier one in the batch is dropped with a comment naming it, the rest lands, and it is taken again once that one landed'

# A batch of 2: the holder left out, #3 behind it takes its place in the same run.
tangled
echo LAND_BATCH_SIZE=2 >> notchcast/config.env
DISPATCH_FAILS=train/1-3 queue
[ "$status" -ne 0 ] && [ "$(landed)" = '' ] && grep -q '^DROPPED #2: #2 contains commits of #1, ' "$FIXTURE/train-output" \
    && grep -q '^queue: batch 1 3$' "$FIXTURE/train-output" || queue_fail 'a batch whose dispatch failed landed or passed, or was not refilled'
queue
[ "$status" -eq 0 ] && grep -q "^queue: #2 waits, dropped at $(jq -r .headRefOid "$FIXTURE/pr-2.json" | cut -c1-8): #2 contains commits of #1$" "$FIXTURE/train-output" \
    && ! grep -q '^DROPPED' "$FIXTURE/train-output" && grep -q '^LANDED #1 3$' "$FIXTURE/train-output" \
    || queue_fail "the PR that holds another's commits was not left out of the batch"
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add one (#3)' ] && ! grep -q -- '--ref train/1-2' "$FIXTURE/dispatched" && ! grep -q '^2 ' "$FIXTURE/closed" \
    || queue_fail "the tangled batch landed '$(landed)'"
[ "$(cat "$FIXTURE/comments")" = "2 Left out of the landing batch at its head $(jq -r .headRefOid "$FIXTURE/pr-2.json"): #2 contains commits of #1, and landing squashes each PR, so #2 can conflict with main once #1 lands. Land #1 first; then #2 gets one merge round, which the landing owner starts when it is next to land." ] \
    || queue_fail "two runs on one head of the holder commented '$(cat "$FIXTURE/comments")'"
queue
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: conflicts with main in src/b.txt: it waits for one merge round, which the landing owner starts when this PR is next to land; nobody merges main into it before that$' "$FIXTURE/train-output" \
    || queue_fail 'the holder was not taken again once the other landed, or did not conflict with main, so the fixture is not #1067'
echo "PASS: --queue leaves out the PR that holds another's commits, fills its place, skips it while that one is open, and takes it again once it landed"

# Four holders of #1 and #6, which conflicts with main, are signed off before the green #7 and #8. The first tick drops
# them and #1 is red alone; the second, on the same heads, trains #7 and #8; a new head on #6 is taken again.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
for pr in 2 3 4 5; do
    open_pr "$pr" "pr-h$pr" "Add H$pr" "src/h$pr.txt"
    git switch --quiet "pr-h$pr"
    git merge --quiet --no-edit pr-b
    repush "$pr" "pr-h$pr"
done
open_pr 6 pr-six 'Add six' src/shared.txt
open_pr 7 pr-c 'Add C' src/c.txt
open_pr 8 pr-one 'Add one' src/one.txt
echo moved > src/shared.txt
git commit --quiet -am 'Main moves shared'
git push --quiet origin main
base=$(git rev-parse HEAD)
for pr in 1 2 3 4 5 6; do jq -r .headRefOid "$FIXTURE/pr-$pr.json"; done > "$FIXTURE/green"
RED_PRS=1 HEAD_CHECKS=pending queue
[ "$status" -eq 1 ] && grep -q '^queue: batch 1 6$' "$FIXTURE/train-output" && grep -q '^DROPPED #6: conflicts with main in src/shared.txt: ' "$FIXTURE/train-output" \
    && [ "$(grep -c '^DROPPED #[2-5]: #[2-5] contains commits of #1, ' "$FIXTURE/train-output")" -eq 4 ] && grep -q '^CULPRIT #1 ' "$FIXTURE/train-output" \
    && [ "$(wc -l < "$FIXTURE/comments")" -eq 6 ] || queue_fail 'the first tick did not drop the holders and the conflict, or #1 was not red alone'
queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 7 8$' "$FIXTURE/train-output" && grep -q '^LANDED #7 8$' "$FIXTURE/train-output" \
    && grep -q "^queue: #6 waits, dropped at $(jq -r .headRefOid "$FIXTURE/pr-6.json" | cut -c1-8): conflicts with main in src/shared.txt$" "$FIXTURE/train-output" \
    && grep -q "^queue: #1 waits, dropped at $(jq -r .headRefOid "$FIXTURE/pr-1.json" | cut -c1-8): Red alone on main [0-9a-f]*$" "$FIXTURE/train-output" \
    && [ "$(grep -c '^queue: #[2-5] waits, dropped at [0-9a-f]\{8\}: #[2-5] contains commits of #1$' "$FIXTURE/train-output")" -eq 4 ] \
    && [ "$(wc -l < "$FIXTURE/comments")" -eq 6 ] && [ "$(landed)" = 'Notchcast: Add C (#7)|Notchcast: Add one (#8)' ] \
    || queue_fail 'PRs dropped at these heads took the batch from the green ones behind them'
git switch --quiet pr-six
git fetch --quiet origin main
git merge --quiet --no-edit -X ours origin/main
git rev-parse HEAD >> "$FIXTURE/green"
repush 6 pr-six
queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 6$' "$FIXTURE/train-output" && grep -q '^LANDED #6$' "$FIXTURE/train-output" \
    || queue_fail 'a dropped PR with a new head was not taken again'
echo 'PASS: --queue skips PRs dropped at their heads, so green PRs behind them land, and takes one again at a new head'

# A refusal an edit or a retry cures is not tied to the head: #1's title names something private until it is fixed.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
jq '.title = "Add FORBIDDEN B"' "$FIXTURE/pr-1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-1.json"
queue
[ "$status" -eq 1 ] && grep -q '^DROPPED #1: dropped from the landing batch: ' "$FIXTURE/train-output" && grep -q '^LANDED #2$' "$FIXTURE/train-output" \
    && ! grep -q 'Left out' "$FIXTURE/comments" || queue_fail 'a PR with a private name in its title was not dropped with a plain comment'
jq '.title = "Add B"' "$FIXTURE/pr-1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-1.json"
queue
[ "$status" -eq 0 ] && grep -q '^LANDED #1$' "$FIXTURE/train-output" || queue_fail 'a title fixed at the same head was not landed on the next tick'
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
VIEW_FAILS=2 queue
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: dropped from the landing batch: its merge onto main failed$' "$FIXTURE/train-output" \
    && grep -q '^LANDED #1$' "$FIXTURE/train-output" || queue_fail 'a failed gh call did not drop only its PR'
queue
[ "$status" -eq 0 ] && grep -q '^LANDED #2$' "$FIXTURE/train-output" || queue_fail 'a PR dropped for one failed gh call was parked'
echo 'PASS: a PR dropped for a refusal its head does not decide (a private title, a failed call) is taken on the next tick'

# #2 conflicts with #1 in the batch and #1 is red alone, so #2 no longer waits on it.
fixture
open_pr 1 pr-one 'Add one' src/shared.txt
open_pr 2 pr-two 'Add two' src/shared.txt
RED_PRS=1 queue
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: conflicts with #1 in the landing batch ' "$FIXTURE/train-output" && grep -q '^CULPRIT #1 ' "$FIXTURE/train-output" \
    || queue_fail '#2 was not left out behind #1, or #1 was not red alone'
queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 2$' "$FIXTURE/train-output" && grep -q '^LANDED #2$' "$FIXTURE/train-output" \
    || queue_fail 'a PR waited behind a PR that was red alone'
echo 'PASS: a PR left out behind a PR of the batch is taken again once that PR cannot be picked'

# #2 conflicts with #1, which land.sh refuses for good on the isolated runner and then on a hosted train.
fixture
open_pr 1 pr-one 'Add one' src/shared.txt
open_pr 2 pr-two 'Add two' src/shared.txt
mkdir -p "$HOME/.config/notchcast"
echo 'notchcast_notify() { cat >> "$FIXTURE/notified"; }' > "$HOME/.config/notchcast/private.env"
ISOLATED='other toolchain|' MAC_RUNNER=fixture-mac queue
grep -q '^DROPPED #2: conflicts with #1 in the landing batch ' "$FIXTURE/train-output" && grep -q '^REFUSED FOR GOOD #1: ' "$FIXTURE/train-output" \
    || queue_fail '#2 was not left out behind #1, or #1 was not refused for good on the isolated runner'
ISOLATED='other toolchain|' MAC_RUNNER=fixture-mac queue
grep -q '^queue: batch 1$' "$FIXTURE/train-output" && grep -q '^REFUSED FOR GOOD #1: .*; the queue leaves these PRs out ' "$FIXTURE/train-output" \
    || queue_fail '#1 was not trained hosted alone and refused for good again'
ISOLATED='fixture toolchain|' MAC_RUNNER=fixture-mac queue
rm "$HOME/.config/notchcast/private.env"
[ "$status" -eq 0 ] && grep -q '^queue: #1 left out: ' "$FIXTURE/train-output" && grep -q '^queue: batch 2$' "$FIXTURE/train-output" \
    && grep -q '^LANDED #2$' "$FIXTURE/train-output" || queue_fail 'a PR waited behind a PR refused for good on a hosted train'
echo 'PASS: a PR left out behind a PR of the batch is taken again once land.sh refused that PR for good on a hosted train'

# Batch of 2: #3 is signed off 30 s ago, so it does not take the holder's place.
tangled
echo LAND_BATCH_SIZE=2 >> notchcast/config.env
echo 2026-03-01T10:00:00Z > "$FIXTURE/ready-1"
echo 2026-03-01T10:00:00Z > "$FIXTURE/ready-2"
echo 2026-03-01T10:09:30Z > "$FIXTURE/ready-3"
NOTCHCAST_NOW=$(jq -n '"2026-03-01T10:10:00Z" | fromdateiso8601') queue
[ "$status" -ne 0 ] && grep -q '^DROPPED #2: #2 contains commits of #1, ' "$FIXTURE/train-output" && grep -q '^queue: batch 1$' "$FIXTURE/train-output" \
    && grep -q '^LANDED #1$' "$FIXTURE/train-output" || queue_fail 'a sign-off younger than the settle time refilled the batch'
echo 'PASS: a sign-off younger than LAND_SETTLE_SECONDS does not refill a place the holder check leaves'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
origin update-ref refs/heads/train/3 "$base"
RED_PRS=2 train 1 2 3
[ "$status" -eq 1 ] && grep -q '^REFUSED: origin already has train/3' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a taken split name was not refused'; }
[ "$(origin for-each-ref --format='%(refname:lstrip=2)' refs/heads/train/)" = train/3 ] && ! grep -q -- '--ref train/1-2 ' "$FIXTURE/dispatched" && untouched \
    || fail "a split refused on a taken name left '$(origin for-each-ref refs/heads/train/)'"
echo 'PASS: a split round whose branch name is taken refuses before pushing any half'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
RED_PRS=2 DISPATCH_FAILS=train/3 train 1 2 3
[ "$status" -eq 1 ] && grep -q 'scrapping train/1-2, which has no verdict' "$FIXTURE/train-output" \
    && grep -q 'scrapping train/3, which has no verdict' "$FIXTURE/train-output" || { cat "$FIXTURE/train-output"; fail 'a failed dispatch scrapped nothing'; }
[ -z "$(origin for-each-ref refs/heads/train/)" ] && untouched || fail "a failed dispatch left '$(origin for-each-ref refs/heads/train/)'"
echo 'PASS: a split round that stops after pushing deletes every half it pushed'

# clipboard-text-test, which the hosted runner skips, is red with src/e.txt; a-test with src/a.txt and src/b.txt.
fixture
open_pr 1 pr-a 'Add A' src/a.txt
open_pr 2 pr-b 'Add B' src/b.txt src/clipboard-text.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
land --train-run "$train_sha" 1 2
[ "$status" -eq 0 ] && grep -q "^harnesses: covered by train ${train_sha:0:8} (same tree, generated files aside)" "$FIXTURE/output" \
    || fail 'a covered train did not report its harnesses as covered'
[ "$(paste -sd'|' "$PASSES")" = clipboard-text-test ] || fail "a covered train ran '$(paste -sd'|' "$PASSES")'"
[ "$(landed)" = 'Notchcast: Add A (#1)|Notchcast: Add B (#2)' ] || fail "a covered train landed '$(landed)'"
echo 'PASS: a covered train runs only the harnesses its hosted runner skips, not the ones the train run passed'

fixture
open_pr 1 pr-a 'Add A' src/a.txt
open_pr 2 pr-e 'Add E' src/clipboard-text.txt src/e.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "^REFUSED: train ${train_sha:0:8}: #2 clipboard-text-test failed; nothing lands on that run" "$FIXTURE/output" && untouched \
    || fail 'a red runner-skipped harness on a train run dropped a PR and landed the rest'
[ -n "$(origin rev-parse --verify -q refs/heads/train/1-2)" ] || fail 'a refused train lost its branch'
echo 'PASS: a red pass on a train run bisects to its breaking PR and lands no part of the train'

# list_pr <number> <name>: a PR that adds its harness to HOSTED_ONLY_TESTS and its item to the first addons.md cell.
list_pr() {
    open_pr "$1" "pr-$2" "Add $2" "src/$2.txt"
    git switch --quiet "pr-$2"
    sed "s/^HOSTED_ONLY_TESTS=\"hosted-test/& nc-$2-test/" notchcast/config.env > "$FIXTURE/edit" && cat "$FIXTURE/edit" > notchcast/config.env
    reword "F1 One" "F1 One, F$1 $2"
    jq '.body = "Drift tooling: fixture list"' "$FIXTURE/pr-$1.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$1.json"
    repush "$1" "pr-$2"
}
# reword <from> <to>: commits the addons.md row with one text replaced.
reword() {
    sed "s/$1/$2/" notchcast/docs/addons.md > "$FIXTURE/edit" && cat "$FIXTURE/edit" > notchcast/docs/addons.md
    git commit --quiet -am "Reword $1"
}
fixture
list_pr 1 timers
list_pr 2 scripts
train 1 2
[ "$status" -eq 0 ] && [ -n "$train_sha" ] || { cat "$FIXTURE/train-output"; echo 'FAIL: two PRs that each add a name to the same lines did not fit one train'; exit 1; }
echo "$train_sha" > "$FIXTURE/green"
land --train-run "$train_sha" 1 2
[ "$status" -eq 0 ] && [ "$(landed)" = 'Notchcast: Add timers (#1)|Notchcast: Add scripts (#2)' ] || fail "the word-merged train landed '$(landed)'"
[ "$(origin show main:notchcast/config.env | grep '^HOSTED_ONLY_TESTS=' | tail -1)" = 'HOSTED_ONLY_TESTS="hosted-test nc-timers-test nc-scripts-test form-input-test"' ] \
    && [ "$(origin show main:notchcast/docs/addons.md)" = '| Launcher | F1 One, F1 timers, F2 scripts | F9 Nine |' ] \
    || fail "the landed lists are '$(origin show main:notchcast/config.env | grep '^HOSTED_ONLY_TESTS=' | tail -1)' and '$(origin show main:notchcast/docs/addons.md)'"
echo 'PASS: two PRs that each add a name to one config.env list and one addons.md cell land in one train, both names kept'

fixture
list_pr 1 timers
for number in 2 3; do
    open_pr "$number" "pr-nine-$number" "Rename nine $number" "src/nine-$number.txt"
    git switch --quiet "pr-nine-$number"
    reword 'F9 Nine' "F9 Nine$number"
    repush "$number" "pr-nine-$number"
done
land 1 2 3
[ "$status" -eq 0 ] && grep -q 'REFUSED: merge conflict: notchcast/docs/addons.md' "$FIXTURE/output" && grep -q 'DROPPED #3' "$FIXTURE/output" \
    || fail 'two PRs that change the same word did not conflict'
[ "$(origin show main:notchcast/docs/addons.md)" = '| Launcher | F1 One, F1 timers | F9 Nine2 |' ] || fail "the row landed as '$(origin show main:notchcast/docs/addons.md)'"
echo 'PASS: a PR that changes a word an earlier PR of the train changed still conflicts and is dropped'

# A PR that changes ci.py tested-key makes a run land.sh never finds: refused before anything is pushed.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-key 'Key' src/k.txt
git switch --quiet pr-key
sed 's/"README.md", /"README.md", "src\/shared.txt", /' notchcast/ci.py > "$FIXTURE/edit" && cat "$FIXTURE/edit" > notchcast/ci.py
git diff --quiet && fail 'the fixture did not change tested-key'
git commit --quiet -am 'Change tested-key'
repush 2 pr-key
train 1 2
[ "$status" -eq 1 ] && grep -q "^REFUSED: the train's run would record tree .* so it could never land: #2 changes ci.py tested-key; land that one first, alone" "$FIXTURE/train-output" \
    && [ ! -e "$FIXTURE/dispatched" ] && [ -z "$(origin for-each-ref refs/heads/train/)" ] || { cat "$FIXTURE/train-output"; fail 'a train whose tested key main cannot compute was pushed'; }
echo 'PASS: a train with a PR that changes tested-key is refused before the push, naming the PR'

# land.sh refuses a squash message naming something private; the train drops that PR before the push.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-f 'Add FORBIDDEN' src/c.txt
train 1 2
grep -q '^DROPPED #2: dropped from the landing batch: commit message names something private$' "$FIXTURE/train-output" \
    && [ "$(origin rev-parse refs/heads/train/1)" = "$train_sha" ] || { cat "$FIXTURE/train-output"; fail 'a PR whose squash message land.sh refuses rode the train'; }
echo 'PASS: a PR whose squash message names something private is dropped before the push'

# One pass names every reason a PR is dropped for: an unlabelled draft that also lacks its Drift tooling line.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-tool 'Tool' notchcast/hold.sh
draft 2
unlabel 2
train 1 2
grep -q "^DROPPED #2: dropped from the landing batch: drift tooling or land.sh changed: the PR body needs a line Drift tooling: <reason>; draft #2 has no land label" "$FIXTURE/train-output" \
    && [ -n "$train_sha" ] || { cat "$FIXTURE/train-output"; fail 'a dropped PR did not get every reason in one pass'; }
echo 'PASS: a dropped PR is told every reason in one pass, and the rest runs'

# A train stopped while it waits, and stopped again while it scraps, still deletes its branch and says how it ended.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
status=0
KILL_TRAIN=1 NOTCHCAST_TRAIN_POLL=0 sh -c 'echo $$ > "$FIXTURE/train-pid"; exec bash notchcast/train.sh 1' > "$FIXTURE/train-output" 2>&1 || status=$?
[ "$status" -eq 143 ] && grep -q '^train: scrapping train/1, which has no verdict' "$FIXTURE/train-output" && grep -q '^train: exit 143$' "$FIXTURE/train-output" \
    && [ -z "$(origin for-each-ref refs/heads/train/)" ] || { cat "$FIXTURE/train-output"; fail "a train stopped twice left $(origin for-each-ref refs/heads/train/) (exit $status)"; }
echo 'PASS: a train stopped during its scrap still deletes its branch and ends with its exit line'

# Stopped while it sleeps between polls, with two trains pushed and one listing failing: both branches go.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
RED_PRS=2 PENDING_TRAINS='1 2' RUN_IDS=1 RUNLIST_FAILS=train/1 NOTCHCAST_TRAIN_POLL=600 bash notchcast/train.sh 1 2 > "$FIXTURE/train-output" 2>&1 &
trainer=$!
# Real time: the stop must land while the train sleeps; each wait is capped at 30 s.
for _ in $(seq 300); do [ -e "$FIXTURE/waiting" ] && pgrep -P "$trainer" sleep > /dev/null && break; sleep 0.1; done
pgrep -P "$trainer" sleep > /dev/null || { kill -KILL "$trainer"; cat "$FIXTURE/train-output"; fail 'the train never slept between polls'; }
kill -TERM "$trainer"
for _ in $(seq 300); do kill -0 "$trainer" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$trainer" 2>/dev/null; then kill -KILL "$trainer"; cat "$FIXTURE/train-output"; fail 'a TERM waited out the poll sleep'; fi
status=0
wait "$trainer" || status=$?
[ "$status" -eq 143 ] && grep -q '^train: exit 143$' "$FIXTURE/train-output" && [ -z "$(origin for-each-ref refs/heads/train/)" ] \
    && [ "$(grep -c '^run cancel 5 ' "$FIXTURE/cancelled")" -eq 2 ] && grep -q 'could not cancel the runs of train/1' "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; fail "a train stopped in its poll sleep left $(origin for-each-ref refs/heads/train/) (exit $status)"; }
echo 'PASS: a train stopped while it sleeps ends at once and scraps every branch, past a failing run listing'

# A bad call with --detach is refused before anything detaches.
fixture
status=0
bash notchcast/train.sh --detach 1 1x > "$FIXTURE/train-output" 2>&1 || status=$?
[ "$status" -eq 2 ] && grep -q '^usage: train.sh \[--detach\]' "$FIXTURE/train-output" && ! grep -q detached "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; fail 'a bad --detach call detached'; }
echo 'PASS: train.sh --detach validates its arguments before it detaches'

# --detach: the train runs in a session of its own, so the shell that started it can go; its log ends with the exit line.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
NOTCHCAST_TRAIN_POLL=0 bash notchcast/train.sh --detach 1 > "$FIXTURE/train-output" 2>&1
log=$(sed -n 's/^train: detached, log //p' "$FIXTURE/train-output")
[ -n "$log" ] || fail 'train.sh --detach named no log'
# Real time: the detached train is no child of this shell; capped at 30 s.
for _ in $(seq 300); do grep -q '^train: exit ' "$log" 2>/dev/null && break; sleep 0.1; done
grep -q "^GREEN train/1 " "$log" && grep -q '^train: exit 0$' "$log" || { cat "$log"; fail 'the detached train did not finish green with its exit line'; }
[ "$(cat "$FIXTURE/sid")" != "$(python3 -c 'import os; print(os.getsid(0))')" ] || fail 'the detached train shares the starting session'
rm "$log"
echo 'PASS: train.sh --detach runs the train in its own session and logs it to the end'

# Batch size 1: #1 signed off long ago, #2 30 s ago; only the batch's own sign-off holds it back.
fixture
echo LAND_BATCH_SIZE=1 >> notchcast/config.env
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
echo 2026-03-01T10:00:00Z > "$FIXTURE/ready-1"
echo 2026-03-01T10:09:30Z > "$FIXTURE/ready-2"
NOTCHCAST_NOW=$(jq -n '"2026-03-01T10:10:00Z" | fromdateiso8601') queue
[ "$status" -eq 0 ] && grep -q '^queue: batch 1$' "$FIXTURE/train-output" && [ "$(landed)" = 'Notchcast: Add B (#1)' ] \
    || queue_fail 'a fresh sign-off behind a full batch held the batch back'
echo 'PASS: the settle time counts only the sign-offs of the batch it takes, so a stream behind a full batch cannot stall it'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
PRLIST_FAILS=1 queue
[ "$status" -eq 1 ] && ! grep -q '^queue: no open PR' "$FIXTURE/train-output" && [ ! -e "$FIXTURE/dispatched" ] && untouched \
    || queue_fail 'a failed PR listing read as nothing to land'
echo 'PASS: --queue fails when it cannot list the open PRs, never reports an idle queue'

mkdir -p "$HOME/.config/notchcast"
echo 'notchcast_notify() { cat >> "$FIXTURE/notified"; }' > "$HOME/.config/notchcast/private.env"
fixture
open_pr 1 pr-b 'Add B' src/b.txt
TIMELINE_FAILS=1 queue
[ "$status" -eq 1 ] && grep -q '^queue: cannot read when #1 was labelled land$' "$FIXTURE/train-output" \
    && ! grep -q '^queue: batch' "$FIXTURE/train-output" && [ ! -e "$FIXTURE/dispatched" ] && untouched \
    && grep -qxF 'Notchcast: the landing queue stopped: it cannot read when #1 was labelled land' "$FIXTURE/notified" \
    || queue_fail 'a failed sign-off lookup landed on a guessed time, or was not notified'
fixture
open_pr 1 pr-b 'Add B' src/b.txt
TIMELINE_EMPTY=1 queue
[ "$status" -eq 1 ] && grep -q '^queue: cannot read when #1 was labelled land$' "$FIXTURE/train-output" \
    && ! grep -q '^queue: batch' "$FIXTURE/train-output" && [ ! -e "$FIXTURE/dispatched" ] && untouched \
    && [ "$(cat "$FIXTURE/notified")" = 'Notchcast: the landing queue stopped: it cannot read when #1 was labelled land' ] \
    || queue_fail 'an empty sign-off lookup landed on a guessed time, or was not notified once'
rm "$HOME/.config/notchcast/private.env"
echo 'PASS: --queue fails and notifies when a sign-off lookup fails or finds no land label, never lands on a guessed time'

# The land lease (#1161): private.env names a stub lock hook that logs each call and refuses while LOCK_EXIT is 1.
cat > "$scratch/bin/land-lock" <<'STUB'
#!/bin/bash
echo "$*" >> "$FIXTURE/lock-log"
[ "${LOCK_EXIT:-0}" -eq 0 ] || { echo 'gate: land is held by queue@other until 12:00' >&2; exit 1; }
[ -z "${LOCK_BROKEN:-}" ] || { echo 'ssh: connect to host home: Connection refused' >&2; exit 255; }
# LOCK_FAIL_AT=<n>: the n-th call fails, as when the gate's home is out of reach for a moment.
[ "$(wc -l < "$FIXTURE/lock-log")" -ne "${LOCK_FAIL_AT:-0}" ] || { echo 'gate: land is held by hand@other until 12:00' >&2; exit 1; }
STUB
chmod +x "$scratch/bin/land-lock"
mkdir -p "$HOME/.config/notchcast"
echo 'NOTCHCAST_LAND_LOCK="land-lock land"' > "$HOME/.config/notchcast/private.env"
holder="queue@$(hostname -s)"
tick() {
    status=0
    NOTCHCAST_TRAIN_POLL=0 bash -c 'echo $$ > "$FIXTURE/queue-pid"; exec bash notchcast/queue.sh "$1"' _ "$FIXTURE/work" \
        > "$FIXTURE/train-output" 2>&1 || status=$?
}
at() { jq -n --arg at "$1" '$at | fromdateiso8601'; }

# Two PRs signed off 60 s apart: a tick 30 s after the second takes none, one 3 min after it lands both in one train.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
echo 2026-03-01T10:00:00Z > "$FIXTURE/ready-1"
echo 2026-03-01T10:01:00Z > "$FIXTURE/ready-2"
NOTCHCAST_NOW=$(at 2026-03-01T10:01:30Z) tick
[ "$status" -eq 0 ] && grep -q '^queue: waits, #2 signed off 30 s ago$' "$FIXTURE/train-output" && [ ! -e "$FIXTURE/dispatched" ] && untouched \
    && [ "$(paste -sd'|' "$FIXTURE/lock-log")" = "land take $holder|land take $holder|land drop $holder" ] \
    || queue_fail 'a tick inside the settle time took a batch, or did not hold and drop the lease'
rm "$FIXTURE/lock-log"
NOTCHCAST_NOW=$(at 2026-03-01T10:04:00Z) tick
[ "$status" -eq 0 ] && grep -q '^queue: batch 1 2$' "$FIXTURE/train-output" && grep -q '^LANDED #1 2$' "$FIXTURE/train-output" \
    && ! grep -q REFUSED "$FIXTURE/train-output" || queue_fail 'a tick after the settle time did not land both in one train'
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] && [ "$(grep -c -- '--ref train/1-2\( \|$\)' "$FIXTURE/dispatched")" -eq 4 ] \
    && [ "$(wc -l < "$FIXTURE/dispatched")" -eq 4 ] || queue_fail "the settled batch landed '$(landed)' from '$(paste -sd'|' "$FIXTURE/dispatched")'"
[ "$(paste -sd'|' "$FIXTURE/lock-log")" = "land take $holder|land take $holder|land take $holder|land drop $holder" ] \
    || queue_fail "the queue's lease calls were '$(paste -sd'|' "$FIXTURE/lock-log")'"
[ "$(git worktree list | wc -l)" -eq 1 ] || queue_fail 'the tick left a worktree behind'
echo 'PASS: PRs signed off a minute apart wait out the settle time and land in one train under the queue lease, dropped at exit'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
LOCK_EXIT=1 tick
[ "$status" -eq 0 ] && grep -q '^queue: the land lease is held; next tick$' "$FIXTURE/train-output" && [ ! -e "$FIXTURE/dispatched" ] && untouched \
    && [ "$(cat "$FIXTURE/lock-log")" = "land take $holder" ] || queue_fail 'a tick under a foreign lease ran a train or dropped the lease'
echo 'PASS: a tick while another holds the land lease runs nothing and leaves that lease alone'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
NOTCHCAST_LAND_LEASE=hand@test train 1
[ "$status" -eq 0 ] && grep -q '^GREEN train/1 ' "$FIXTURE/train-output" && [ "$(cat "$FIXTURE/lock-log")" = 'land take hand@test' ] \
    || queue_fail 'a train under a granted lease did not run'
NOTCHCAST_LAND_LEASE=hand@test land --train-run "$train_sha" 1
[ "$status" -eq 0 ] && [ "$(landed)" = 'Notchcast: Add B (#1)' ] && [ "$(paste -sd'|' "$FIXTURE/lock-log")" = 'land take hand@test|land take hand@test' ] \
    || fail 'land.sh under a granted lease did not land, or did not renew it'
rm "$FIXTURE/lock-log"
land --check "$base" "$(origin rev-parse main)"
[ "$status" -eq 0 ] && grep -q '^PASS: merged-tree harnesses$' "$FIXTURE/output" || fail 'land.sh --check needed a lease'
land --guard
[ "$status" -eq 0 ] && [ ! -e "$FIXTURE/lock-log" ] || fail 'land.sh --guard needed a lease, or --check or --guard called the hook'
echo 'PASS: under the lock hook a granted lease trains and lands, renewing it; --check and --guard need none'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
status=0
NOTCHCAST_LAND_FORCE=1 NOTCHCAST_TRAIN_POLL=0 python3 -c 'import os, pty, sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))' \
    bash notchcast/train.sh --queue > "$FIXTURE/train-output" 2>&1 < /dev/null || status=$?
[ "$status" -eq 0 ] && grep -q '^FORCED: landing outside the queue' "$FIXTURE/train-output" && grep -q '^LANDED #1' "$FIXTURE/train-output" \
    && [ "$(landed)" = 'Notchcast: Add B (#1)' ] && [ ! -e "$FIXTURE/lock-log" ] || queue_fail 'a train forced from a terminal did not land'
echo 'PASS: a train forced from a terminal lands without the lease, its land.sh forced too'

# The third take (land.sh's renewal) is refused: tick 1 keeps its green train/1, tick 2 scraps it and lands.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
LOCK_FAIL_AT=3 tick
[ "$status" -eq 1 ] && grep -q '^NOT LANDED #1' "$FIXTURE/train-output" && [ -n "$(origin for-each-ref refs/heads/train/1)" ] && untouched \
    && [ "$(tail -1 "$FIXTURE/lock-log")" = "land drop $holder" ] || queue_fail 'a refused renewal at landing did not keep its train and drop the lease'
tick
[ "$status" -eq 0 ] && grep -q '^train: train/1 is left from an earlier run; scrapping it$' "$FIXTURE/train-output" && grep -q '^LANDED #1$' "$FIXTURE/train-output" \
    && [ "$(landed)" = 'Notchcast: Add B (#1)' ] && [ -z "$(origin for-each-ref refs/heads/train/)" ] \
    || queue_fail 'a train branch left by an earlier tick jammed the queue'
echo "PASS: a tick whose renewal is refused at landing leaves no jam: the next tick scraps the leftover train branch and lands"

# TERM to the tick while its train waits on CI: the train scraps its branch, then the tick drops the lease and its tree.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
STOP_QUEUE=1 tick
[ "$status" -eq 143 ] && grep -q '^train: scrapping train/1, which has no verdict' "$FIXTURE/train-output" && grep -q '^train: exit 143$' "$FIXTURE/train-output" \
    && [ -z "$(origin for-each-ref refs/heads/train/)" ] && untouched && [ "$(git worktree list | wc -l)" -eq 1 ] \
    && [ "$(paste -sd'|' "$FIXTURE/lock-log")" = "land take $holder|land take $holder|land drop $holder" ] \
    || queue_fail 'a stopped tick did not stop its train, scrap its branch and drop the lease'
echo 'PASS: a tick stopped mid-train stops the train, which scraps its branch, then drops the lease and removes its tree'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
git remote set-url origin "$FIXTURE/no-such-origin.git"
tick
git remote set-url origin "$FIXTURE/origin.git"
[ "$status" -ne 0 ] && [ "$(paste -sd'|' "$FIXTURE/lock-log")" = "land take $holder|land drop $holder" ] && [ "$(git worktree list | wc -l)" -eq 1 ] \
    && [ ! -e "$FIXTURE/dispatched" ] || queue_fail 'a tick whose fetch failed kept the lease'
echo 'PASS: a tick whose fetch fails still drops the lease'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
LOCK_BROKEN=1 tick
[ "$status" -eq 1 ] && grep -q '^queue: could not take the land lease$' "$FIXTURE/train-output" && grep -q 'Connection refused' "$FIXTURE/train-output" \
    && ! grep -q 'is held' "$FIXTURE/train-output" && [ ! -e "$FIXTURE/dispatched" ] && untouched \
    || queue_fail 'a failing hook was logged as a held lease'
echo 'PASS: a hook that fails is logged as a failure, exit 1, never as a held lease'

rm -f "$HOME/.config/notchcast/private.env"
fixture
open_pr 1 pr-b 'Add B' src/b.txt
tick
[ "$status" -eq 1 ] && grep -q '^queue: no NOTCHCAST_LAND_LOCK in private.env' "$FIXTURE/train-output" && [ ! -e "$FIXTURE/dispatched" ] && untouched \
    || queue_fail 'a queue without the lock hook ran'
echo 'PASS: queue.sh runs nothing without the lock hook'

# Last: a killed lander can leave children behind.
for signal in TERM HUP; do
    fixture
    open_pr 1 pr-b 'Add B' src/b.txt
    : > "$FIXTURE/slow"
    bash notchcast/land.sh 1 > "$FIXTURE/output" 2>&1 &
    lander=$!
    for _ in $(seq 600); do [ -s "$FIXTURE/started" ] && break; sleep 0.1; done
    [ -s "$FIXTURE/started" ] || fail "the $signal lander never reached its harnesses"
    [ -s "$FIXTURE/hold" ] || fail "no hold while the harnesses ran"
    kill -"$signal" "$lander"
    status=0
    wait "$lander" || status=$?
    [ "$status" -ne 0 ] && [ ! -e "$FIXTURE/hold" ] || fail "a $signal left the hold behind (exit $status)"
done
echo 'PASS: a lander killed by TERM or HUP during its harnesses releases its hold'
fixture
open_pr 1 pr-b 'Add B' src/b.txt
: > "$FIXTURE/slow"
bash notchcast/land.sh 1 > "$FIXTURE/output" 2>&1 &
lander=$!
for _ in $(seq 600); do [ -s "$FIXTURE/started" ] && break; sleep 0.1; done
[ -s "$FIXTURE/started" ] || fail 'the lander never reached its harnesses'
kill -KILL "$lander" "$(cat "$FIXTURE/started")"  # the harness too, or it writes into the next fixture
wait "$lander" || true
[ -s "$FIXTURE/hold" ] || fail 'a SIGKILL ran the EXIT trap'
rm "$FIXTURE/slow"
land 1
[ "$status" -eq 0 ] && [ "$(landed)" = 'Notchcast: Add B (#1)' ] && [ ! -e "$FIXTURE/hold" ] || fail 'the hold of a killed lander refused the next one'
echo 'PASS: the next lander on the Mac takes over the hold of one killed by SIGKILL'
