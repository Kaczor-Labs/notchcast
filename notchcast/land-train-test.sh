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
    *issues/*/timeline*)
        pr=${2#*issues/}
        cat "$FIXTURE/ready-${pr%%/*}" 2>/dev/null || true ;;
    'pr view '*'--json headRefOid'*) jq -r .headRefOid "$FIXTURE/pr-$3.json" ;;
    'pr view '*) cat "$FIXTURE/pr-$3.json" ;;
    'pr close '*)
        echo "$3 ${*: -1}" >> "$FIXTURE/closed"
        jq '.state = "CLOSED"' "$FIXTURE/pr-$3.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-$3.json" ;;
    *check-runs*)
        sha=$*
        sha=${sha#*commits/}
        if grep -qxF "${sha%%/*}" "$FIXTURE/red" 2>/dev/null; then echo failure
        elif grep -qxF "${sha%%/*}" "$FIXTURE/green" 2>/dev/null; then echo success; else echo "${HEAD_CHECKS:-success}"; fi ;;
    'workflow run '*)
        [[ -z "${DISPATCH_FAILS:-}" || "$*" != *"--ref $DISPATCH_FAILS "* ]] || { echo 'HTTP 422' >&2; exit 1; }
        echo "$*" >> "$FIXTURE/dispatched" ;;
    'run list '*databaseId,status*) ;;
    'run list '*headSha,url*)
        branch=$*
        branch=${branch#*-b }
        echo "https://fixture.invalid/red/${branch%% *}" ;;
    # A dispatched train run is red when its branch train/<a>-<b> names a PR in RED_PRS.
    'run list '*workflow_dispatch*)
        branch=$*
        branch=${branch#*-b train/}
        verdict=success
        for pr in ${RED_PRS:-}; do
            [[ "-${branch%% *}-" != *"-$pr-"* ]] || verdict=failure
        done
        echo "$verdict" ;;
    *statuses*) ;;
    # ISOLATED is "<toolchain>|<excused harnesses>": the isolated runner's record of the tree, run 8.
    *'artifacts?name=tested-tree-isolated-'*) if [ -n "${ISOLATED:-}" ]; then echo '{"artifacts":[{"workflow_run":{"id":8}}]}'; else echo '{"artifacts":[]}'; fi ;;
    *actions/runs/8*) printf '{"id":8,"name":"PR","path":".github/workflows/pr.yml","conclusion":"success","head_repository":{"full_name":"%s"},"html_url":"https://fixture.invalid/runs/8"}\n' "$FORK_REPO" ;;
    'run download 8 '*)
        echo "${ISOLATED%%|*}" > "${*: -1}/toolchain"
        echo "${ISOLATED#*|}" > "${*: -1}/excused" ;;
    *actions/runners*) [ -n "${OFFLINE:-}" ] || echo "${MAC_RUNNER:-}" ;;
    'variable get NOTCHCAST_MAC_RUNNER'*) [ -n "${MAC_RUNNER:-}" ] && echo "$MAC_RUNNER" || { echo 'variable NOTCHCAST_MAC_RUNNER was not found' >&2; exit 1; } ;;
    *actions/artifacts*) if [ -n "${TESTED:-}" ]; then echo '{"artifacts":[{"workflow_run":{"id":7}}]}'; else echo '{"artifacts":[]}'; fi ;;
    *actions/runs/7*) printf '{"name":"PR","path":".github/workflows/pr.yml","conclusion":"success","head_repository":{"full_name":"%s"},"html_url":"https://fixture.invalid/runs/7"}\n' "$FORK_REPO" ;;
    'variable get LANDING_HOLD'*) [ -s "$FIXTURE/hold" ] && cat "$FIXTURE/hold" || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; } ;;
    'variable set LANDING_HOLD'*) echo "${*: -1}" > "$FIXTURE/hold" ;;
    'variable delete LANDING_HOLD'*) rm -f "$FIXTURE/hold" ;;
    'run list '*) ;;
    *) echo "gh stub: unexpected $*" >&2; exit 3 ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/swiftc"
chmod +x "$scratch/bin/gh" "$scratch/bin/swiftc"
cp "$root"/notchcast/{land.sh,train.sh,merge.sh,merge-words.py,local-build-status.sh,drift-gates.sh,sync-wait.sh,hold.sh,config.env,fork-point.sh,land-tooling.txt,ci.py,app-proof.py,app-proofs.json} "$seed/notchcast/"
for name in check-drift.py check-drift-test.py; do
    printf '#!/usr/bin/env python3\n' > "$seed/notchcast/$name"
done
# The fixture's own hosted-runner skip, so it never depends on the real list.
echo 'CI_SKIP_TESTS="clipboard-text-test"' >> "$seed/notchcast/config.env"
echo 'HOSTED_ONLY_TESTS="hosted-test"' >> "$seed/notchcast/config.env"
echo 'LINUX_OK_TESTS="notchcast-core-test hosted-test"' >> "$seed/notchcast/config.env"
echo 'ISOLATED_TOOLCHAIN="fixture toolchain"' >> "$seed/notchcast/config.env"
unset RUNNER_ENVIRONMENT NOTCHCAST_ISOLATED_RUNNER
printf '#!/bin/sh\n' > "$seed/notchcast/check-identity.sh"
printf '#!/bin/sh\n' > "$seed/notchcast/check-bundle-readme.sh"
# Selects core, and <name>-test for a changed src/<name>.txt, as changed-harnesses.sh does from harness inputs.
cat > "$seed/notchcast/changed-harnesses.sh" <<'STUB'
#!/bin/bash
# --linux <file>: every harness of the fixture is linux-ok, so no reason is written.
if [ "$1" = --linux ]; then : > "$2"; shift 2; fi
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
for name in notchcast-core b c clipboard-text hosted; do
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
# open_pr <number> <branch> <title> <path>...: a ready PR on origin whose head writes its title into each path.
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
        '{number: $number, createdAt: "2026-01-0\($number)T00:00:00Z", comments: [], state: "OPEN", isDraft: false, headRefOid: $head, headRefName: $branch, baseRefName: "main", isCrossRepository: false, title: $title, body: "", labels: []}' \
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
[ ! -e "$FIXTURE/hold" ] || fail 'the train left its hold behind'
echo 'PASS: a 2-PR train lands one squash per PR after one harness pass over the union of their selections'

# #2 is stacked on #1's branch: GitHub would close it when that branch is deleted.
fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
jq '.baseRefName = "pr-b"' "$FIXTURE/pr-2.json" > "$FIXTURE/pr.json" && mv "$FIXTURE/pr.json" "$FIXTURE/pr-2.json"
land 1
[ "$status" -eq 0 ] && grep -q '^retargeted #2 from pr-b to main$' "$FIXTURE/output" || fail 'landing #1 did not say it moved the PR stacked on its branch'
[ "$(cat "$FIXTURE/retargeted")" = '2 pr-b 1' ] && [ -z "$(origin for-each-ref refs/heads/pr-b)" ] \
    && [ "$(jq -r '.state + " " + .baseRefName' "$FIXTURE/pr-2.json")" = 'OPEN main' ] || fail 'the stacked PR was not moved to main before its base was deleted'
echo 'PASS: a PR stacked on a landed branch is moved to main, and said so, before that branch is deleted'

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
[ "$status" -eq 1 ] && [ "$(origin rev-parse main)" = "$base" ] && [ ! -s "$PASSES" ] \
    && grep -q "^REFUSED: the isolated run https://fixture.invalid/runs/8 tested this tree with 'other toolchain', and landing expects 'fixture toolchain'" "$FIXTURE/output" \
    || fail 'an isolated run with another toolchain was not refused'
echo 'PASS: an isolated run of the tree with a toolchain landing does not expect is refused'
ISOLATED='fixture toolchain|hosted-test' land 1
[ "$status" -eq 1 ] && [ "$(origin rev-parse main)" = "$base" ] && [ ! -s "$PASSES" ] \
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
untouched() { [ "$(origin rev-parse main)" = "$base" ] && [ ! -e "$FIXTURE/closed" ] && [ ! -e "$FIXTURE/hold" ]; }

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
train 1 2
[ "$status" -eq 0 ] && [ -n "$train_sha" ] || { cat "$FIXTURE/train-output"; fail 'a green train did not report its run'; }
[ "$(origin rev-parse refs/heads/train/1-2)" = "$train_sha" ] && [ "$(origin rev-parse "$train_sha~2")" = "$base" ] \
    && [ "$(origin rev-parse "$train_sha^2")" = "$(jq -r .headRefOid "$FIXTURE/pr-2.json")" ] || fail 'train/1-2 is not main plus each head'
[ "$(grep -c -- '--ref train/1-2' "$FIXTURE/dispatched")" -eq 4 ] && [ "$(grep -c "base=$base" "$FIXTURE/dispatched")" -eq 3 ] \
    && [ "$(grep -c 'hosted=true' "$FIXTURE/dispatched")" -eq 1 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" \
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

# While the repository variable names a runner the train's Mac job goes there, and land.sh judges that run's record.
fixture
open_pr 1 pr-h 'Add H' src/hosted.txt
MAC_RUNNER=fixture-mac NOTCHCAST_TRAIN_MAC=hosted train 1
[ "$status" -eq 0 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^train: train/1 has its Mac job on the hosted runner$' "$FIXTURE/train-output" || fail 'NOTCHCAST_TRAIN_MAC=hosted did not keep the train hosted'
origin push --quiet . --delete train/1 2>/dev/null || origin update-ref -d refs/heads/train/1
rm "$FIXTURE/dispatched"
OFFLINE=1 MAC_RUNNER=fixture-mac train 1
[ "$status" -eq 0 ] && grep -q '^workflow run pr.yml .*hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^train: no runner labelled fixture-mac is online, so the Mac job is hosted$' "$FIXTURE/train-output" \
    || fail 'a train went to a named runner that is offline'
echo 'PASS: a train stays hosted while no runner with the named label is online'
origin push --quiet . --delete train/1 2>/dev/null || origin update-ref -d refs/heads/train/1
rm "$FIXTURE/dispatched"
MAC_RUNNER=fixture-mac train 1
[ "$status" -eq 0 ] && [ -n "$train_sha" ] && grep -q '^workflow run pr.yml ' "$FIXTURE/dispatched" && ! grep -q 'hosted=true' "$FIXTURE/dispatched" \
    && grep -q '^train: train/1 has its Mac job on the isolated runner$' "$FIXTURE/train-output" || fail "with a runner named the train dispatched '$(paste -sd'|' "$FIXTURE/dispatched")'"
echo "$train_sha" > "$FIXTURE/green"
ISOLATED='other toolchain|' land --train-run "$train_sha" 1
[ "$status" -eq 1 ] && grep -q "^REFUSED: the isolated run .* tested this tree with 'other toolchain'" "$FIXTURE/output" && untouched \
    || fail 'a train whose isolated run has another toolchain landed'
ISOLATED='fixture toolchain|' land --train-run "$train_sha" 1
[ "$status" -eq 0 ] && [ ! -s "$PASSES" ] && [ "$(landed)" = 'Notchcast: Add H (#1)' ] || fail "a train proven by the isolated runner landed '$(landed)'"
echo 'PASS: a train goes to the named Mac runner unless told hosted, and lands on its isolated run only with the expected toolchain'

fixture
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
train 1 2
echo "$train_sha" > "$FIXTURE/green"
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2 3
[ "$status" -eq 1 ] && grep -q "does not merge #3's head" "$FIXTURE/output" && grep -q '^REFUSED: [a-z]* is failure on' "$FIXTURE/output" && untouched \
    || fail 'a train run missing a PR head was not refused by the heads own checks'
echo 'PASS: a train run missing a PR head covers nothing and the heads own red checks refuse'

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
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q "does not merge #2's head" "$FIXTURE/output" && grep -q '^REFUSED: [a-z]* is failure on' "$FIXTURE/output" && untouched \
    || fail 'a PR head moved after the train was not refused'
echo 'PASS: a PR head that moved after the train run is refused as without a train'

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
HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
[ "$status" -eq 1 ] && grep -q 'not current main' "$FIXTURE/output" && grep -q '^REFUSED: [a-z]* is failure on' "$FIXTURE/output" && untouched \
    || fail 'a train run on a stale base was not refused'
echo 'PASS: a train run whose base is no longer main is refused as without a train'

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
    HEAD_CHECKS=failure land --train-run "$train_sha" 1 2
    if [ "$moved" = Tinycast.xcodeproj/project.pbxproj ]; then
        [ "$status" -eq 0 ] && grep -q 'only in generated files; the run still proves it' "$FIXTURE/output" \
            && [ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add C (#2)' ] || fail 'a train run did not land after main moved only in generated files'
        [ "$(origin rev-parse main~2)" = "$base" ] && [ "$(origin show main:Tinycast.xcodeproj/project.pbxproj)" = moved ] \
            && [ "$(origin diff --no-renames --name-only "$train_sha" main)" = Tinycast.xcodeproj/project.pbxproj ] || fail 'the landing is not the tested tree on the moved main'
        [ ! -s "$PASSES" ] && [ -z "$(origin for-each-ref refs/heads/train/)" ] || fail 'the proven train ran harnesses again or kept its branch'
    else
        [ "$status" -eq 1 ] && grep -q 'not current main' "$FIXTURE/output" && grep -q '^REFUSED: [a-z]* is failure on' "$FIXTURE/output" && untouched \
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
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: conflicts with main; rebase on main$' "$FIXTURE/train-output" \
    || { cat "$FIXTURE/train-output"; fail 'a train of one PR that conflicts with main was not dropped'; }
[ -z "$(origin for-each-ref refs/heads/train/)" ] && [ ! -e "$FIXTURE/dispatched" ] && untouched || fail 'a train with no PR left pushed or dispatched'
echo 'PASS: a train whose every merge is refused pushes no branch and dispatches nothing'

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
    [ "$status" -eq 1 ] && grep -q '^REFUSED: #2 contains commits of #1, .* so #2 can conflict with main once #1 lands\. Land #1 first, then merge main into #2\.$' "$FIXTURE/train-output" \
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

# #2 was marked ready before #1 was opened; #3 is red on its head, #4 an unlabelled draft, #5 is past the batch size.
fixture
echo LAND_BATCH_SIZE=2 >> notchcast/config.env
open_pr 1 pr-b 'Add B' src/b.txt
open_pr 2 pr-c 'Add C' src/c.txt
open_pr 3 pr-one 'Add one' src/one.txt
open_pr 4 pr-d 'Add D' src/d.txt
open_pr 5 pr-a 'Add A' src/a.txt
echo 2025-12-01T00:00:00Z > "$FIXTURE/ready-2"
jq -r .headRefOid "$FIXTURE/pr-3.json" > "$FIXTURE/red"
draft 4
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
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: conflicts with #1 in the landing batch; rebase on main$' "$FIXTURE/train-output" \
    && [ "$(cat "$FIXTURE/comments")" = '2 conflicts with #1 in the landing batch; rebase on main' ] || queue_fail 'the later conflicting PR was not dropped and told'
[ "$(landed)" = 'Notchcast: Add one (#1)|Notchcast: Add C (#3)' ] && [ "$(grep -c -- '--ref train/1-3\( \|$\)' "$FIXTURE/dispatched")" -eq 4 ] \
    && ! grep -q '^2 ' "$FIXTURE/closed" || queue_fail "the conflict batch landed '$(landed)'"
echo 'PASS: a PR that conflicts with an earlier one in the batch is dropped with a comment naming it, and the rest lands'

tangled
DISPATCH_FAILS=train/1-3 queue
[ "$status" -ne 0 ] && [ "$(landed)" = '' ] || queue_fail 'a batch whose dispatch failed landed or passed'
queue
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: #2 contains commits of #1, ' "$FIXTURE/train-output" && grep -q '^LANDED #1 3$' "$FIXTURE/train-output" \
    || queue_fail "the PR that holds another's commits was not left out of the batch"
[ "$(landed)" = 'Notchcast: Add B (#1)|Notchcast: Add one (#3)' ] && ! grep -q -- '--ref train/1-2' "$FIXTURE/dispatched" && ! grep -q '^2 ' "$FIXTURE/closed" \
    || queue_fail "the tangled batch landed '$(landed)'"
[ "$(cat "$FIXTURE/comments")" = "2 Left out of the landing batch at its head $(jq -r .headRefOid "$FIXTURE/pr-2.json"): #2 contains commits of #1, and landing squashes each PR, so #2 can conflict with main once #1 lands. Land #1 first, then merge main into #2." ] \
    || queue_fail "two runs on one head of the holder commented '$(cat "$FIXTURE/comments")'"
base=$(origin rev-parse main)
train 2
[ "$status" -eq 1 ] && grep -q '^DROPPED #2: conflicts with main; rebase on main$' "$FIXTURE/train-output" \
    || queue_fail 'the holder did not conflict with main once the other landed, so the fixture is not #1067'
echo "PASS: --queue leaves out the PR that holds another's commits, tells it once per head what to do, and lands the rest"

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
[ "$status" -eq 0 ] && [ -n "$train_sha" ] || { cat "$FIXTURE/train-output"; fail 'two PRs that each add a name to the same lines did not fit one train'; }
echo "$train_sha" > "$FIXTURE/green"
land --train-run "$train_sha" 1 2
[ "$status" -eq 0 ] && [ "$(landed)" = 'Notchcast: Add timers (#1)|Notchcast: Add scripts (#2)' ] || fail "the word-merged train landed '$(landed)'"
[ "$(origin show main:notchcast/config.env | grep '^HOSTED_ONLY_TESTS=' | tail -1)" = 'HOSTED_ONLY_TESTS="hosted-test nc-timers-test nc-scripts-test"' ] \
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
