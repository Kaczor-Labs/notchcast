#!/bin/bash
set -euo pipefail
# A stale checkout lands by stale rules (one skipped the Sync wait), so a landing always runs main's tooling.
if [ "$#" -ge 1 ] && [ "$1" != --check ] && [ -z "${NOTCHCAST_LAND_TOOLS:-}" ]; then
    origin_top=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
    git -C "$origin_top" fetch --quiet origin main || { echo 'REFUSED: could not fetch origin main' >&2; exit 1; }
    if [ "$(git -C "$origin_top" rev-parse HEAD:notchcast)" != "$(git -C "$origin_top" rev-parse origin/main:notchcast)" ] \
        || ! git -C "$origin_top" diff --quiet HEAD -- notchcast; then
        tools=$(mktemp -d)
        git -C "$origin_top" worktree add --quiet --detach "$tools/tree" origin/main
        echo "land.sh: this checkout's notchcast/ differs from origin/main; running main's copy"
        cd "$tools/tree"
        NOTCHCAST_LAND_TOOLS=$tools NOTCHCAST_LAND_ORIGIN=$origin_top exec bash notchcast/land.sh "$@"
    fi
fi
remove_tools() {
    [ -z "${hold_claimed:-}" ] || hold_release_claimed  # both EXIT traps run this
    [ -n "${NOTCHCAST_LAND_ORIGIN:-}" ] || return 0
    cd "$NOTCHCAST_LAND_ORIGIN"
    git worktree remove --force "$NOTCHCAST_LAND_TOOLS/tree" >/dev/null 2>&1 || true
    rm -rf "$NOTCHCAST_LAND_TOOLS"
}
trap remove_tools EXIT
trap 'exit 1' HUP INT TERM
source "$(dirname "$0")/local-build-status.sh"
selector="$(cd "$(dirname "$0")" && pwd)/changed-harnesses.sh"
cd "$(git rev-parse --show-toplevel)"
source "$(dirname "$0")/merge.sh"
delete_head() {
    local name=$1 expected=$2 fork=${3:-false} remote local_head stacked pr kept=
    [ "$fork" = false ] || return 0
    remote=$(git ls-remote origin "refs/heads/$name") || { echo 'WARN: cannot read origin head' >&2; return 0; }
    if [ "${remote%%[[:space:]]*}" = "$expected" ]; then
        # GitHub closes every open PR based on a deleted branch, so each moves to main first.
        stacked=$(gh pr list -R "$FORK_REPO" --base "$name" --state open --limit 1000 --json number --jq '.[].number') \
            || { echo "WARN: kept origin/$name: cannot list PRs based on it" >&2; kept=1; }
        for pr in $stacked; do
            if gh pr edit "$pr" -R "$FORK_REPO" --base main >/dev/null; then
                echo "retargeted #$pr from $name to main"
            else
                echo "WARN: kept origin/$name: PR #$pr still targets it" >&2
                kept=1
            fi
        done
        [ -n "$kept" ] || git push origin --delete "$name" || echo "WARN: could not delete origin/$name" >&2
    fi
    local_head=$(git rev-parse --verify "refs/heads/$name" 2>/dev/null) || return 0
    if [ "$local_head" = "$expected" ]; then
        git branch -D -- "$name" || echo "WARN: could not delete local $name (possibly checked out)" >&2
    fi
    return 0
}
source "$(dirname "$0")/sync-wait.sh"
source "$(dirname "$0")/hold.sh"
# Optional maintainer hooks (README, "Private hooks"): notchcast_mac_route and notchcast_notify.
[ ! -f "$HOME/.config/notchcast/private.env" ] || source "$HOME/.config/notchcast/private.env"
# Where the harness proof runs: a Mac runs every harness, anything else only LINUX_OK_TESTS (config.env).
case "${NOTCHCAST_PLATFORM:-$(uname -s)}" in Darwin) platform=mac ;; *) platform=linux ;; esac
landed_from=mac
as_maintainer() {
    GIT_AUTHOR_NAME="$MAINTAINER_NAME" GIT_AUTHOR_EMAIL="$MAINTAINER_EMAIL" \
        GIT_COMMITTER_NAME="$MAINTAINER_NAME" GIT_COMMITTER_EMAIL="$MAINTAINER_EMAIL" "$@"
}
tell_keeper() {
    echo "KEEPER: $1" >&2
    ! declare -F notchcast_notify >/dev/null || printf 'Notchcast: %s\n' "$1" | notchcast_notify || echo 'WARN: notify failed' >&2
}
# Ends this run with exit 4: the landing needs a Mac, so it is handed over, neither landed nor refused.
route() {
    if [ "$check" -eq 1 ]; then echo "ROUTED: this diff lands from a Mac, not from Linux: $1"; exit 4; fi
    echo "ROUTED: #${train[*]} goes to a Mac, not landed here: $1"
    if declare -F notchcast_mac_route >/dev/null; then
        notchcast_mac_route "${train[@]}" || echo 'WARN: the Mac route failed; land it on a Mac by hand' >&2
    else
        echo "No Mac route here (notchcast_mac_route, private.env); on a Mac run: notchcast/land.sh ${train[*]}"
    fi
    exit 4
}
# Where commit $1's harness proof ran, from its message: linux, mac, or nothing for an older or foreign commit.
landed_from_of() { git show -s --format='%(trailers:key=Landed-from,valueonly)' "$1" | grep -m1 . || true; }
# The follow-up of a Linux landing, kept as a commit status: none until judged, then success or failure.
followup() {
    gh api "repos/$FORK_REPO/commits/$1/statuses?per_page=100" \
        --jq "[.[] | select(.context == \"$FOLLOWUP_CONTEXT\")] | sort_by(.id) | last | .state // \"none\""
}
judge() {
    gh api "repos/$FORK_REPO/statuses/$1" -f state="$2" -f context="$FOLLOWUP_CONTEXT" -f description="$3" >/dev/null \
        || echo "WARN: could not record the follow-up of ${1:0:8}" >&2
}
# The macOS suite's verdict on main commit $1, from Snapshot, which tests each pushed main: green, "red <run url>",
# or pending. A newer push cancels the run in flight, and a red signing step is not a harness verdict.
mac_verdict() {
    local run
    run=$(gh run list -R "$FORK_REPO" -w snapshot.yml --commit "$1" --json databaseId,status,conclusion \
        --jq '[.[] | select(.status == "completed" and .conclusion != "cancelled" and .conclusion != "skipped")] | max_by(.databaseId) | .databaseId // empty') || run=
    [ -n "$run" ] || { echo pending; return 0; }
    gh run view "$run" -R "$FORK_REPO" --json jobs,url --jq '. as $run | [.jobs[].steps[]?]
        | if any(.name == "Fail when a planned snapshot was skipped" and .conclusion == "failure") then "red \($run.url)"
          elif any(.name == "Lint" and .conclusion == "success") then "green" else "pending" end' || echo pending
}
# Reverts Linux landing $1 (main's tip, red at run $2) with a revert PR landed here, and reopens its PR.
auto_revert() {
    local sha=$1 url=$2 pr failed revert number name
    [[ "$(git show -s --format=%s "$sha")" =~ \(#([0-9]+)\)$ ]] || return 1
    pr=${BASH_REMATCH[1]}
    failed=$(gh run view "${url##*/}" -R "$FORK_REPO" --log 2>/dev/null | sed -n 's/.*harness(es) failed in [0-9]*s: //p' | tail -1) || failed=
    [ -n "$failed" ] || return 1  # red for lint or infrastructure: nothing says the landing broke a harness
    tree_at "$sha"
    git revert --no-commit "$sha" >/dev/null 2>&1 || return 1
    # The cause joins LINUX_DENY_INPUTS in the revert itself, so the PR's next landing goes to a Mac.
    python3 "$(dirname "$selector")/linux-deny.py" "$sha^" "$sha" $failed
    git add notchcast/config.env
    printf 'Notchcast: revert #%s, red on macOS after its Linux landing\n\n%s failed: %s\n\nLanded-from: mac\n' "$pr" "$failed" "$url" > "$scratch/message"
    revert=$(as_maintainer git commit-tree "$(git write-tree)" -p "$sha" -F "$scratch/message")
    git push -q origin "$revert:refs/heads/revert-$pr" || return 1
    number=$(gh pr create -R "$FORK_REPO" --head "revert-$pr" --base main --title "Notchcast: revert #$pr, red on macOS after its Linux landing" \
        --body "#$pr landed from Linux and the macOS suite on main went red: $url ($failed). Reverted by notchcast/land.sh --guard.") || return 1
    number=${number##*/}
    # Plain, never forced: it lands only while the Linux landing is still main's tip.
    git push -q origin "$revert:refs/heads/main" || return 1
    gh pr close "$number" -R "$FORK_REPO" --comment "Landed on main as $revert by notchcast/land.sh --guard: revert of $sha." || true
    git push -q origin --delete "revert-$pr" || true
    name=$(gh pr view "$pr" -R "$FORK_REPO" --json headRefName --jq .headRefName)
    git fetch -q origin "refs/pull/$pr/head" && git push -q origin "FETCH_HEAD:refs/heads/$name" \
        && gh pr reopen "$pr" -R "$FORK_REPO" --comment "Reverted on main as $revert: this PR landed from Linux as $sha and the macOS suite then failed ($failed): $url. Its inputs joined LINUX_DENY_INPUTS, so it lands from a Mac next." \
        || echo "WARN: could not reopen #$pr; reopen it by hand" >&2
    judge "$sha" failure "red on macOS; reverted by #$number"
    tell_keeper "#$pr landed from Linux and went red on macOS ($failed): reverted on main as ${revert:0:8} by #$number, #$pr reopened. $url"
}
# Judges each unjudged Linux landing among main's last commits by the first macOS run at or above it. Red: the only
# change since a green main and still main's tip is reverted; anything else goes to the keeper, never a revert.
guard() {
    local tip sha verdict=pending judged= unjudged pr seen
    git fetch -q origin main || refuse 'cannot fetch origin main'
    tip=$(git rev-parse origin/main)
    unjudged=$(for sha in $(git rev-list -n "${NOTCHCAST_GUARD_DEPTH:-15}" "$tip"); do
        [ "$(landed_from_of "$sha")" != linux ] || [ "$(followup "$sha")" != none ] || echo "$sha"
    done)
    [ -n "$unjudged" ] || return 0
    # Tip first: each commit takes the verdict of the lowest run at or above it, the first run that tested it.
    for sha in $(git rev-list "${unjudged##*$'\n'}^..$tip"); do
        seen=$(mac_verdict "$sha")
        [ "$seen" = pending ] || { verdict=$seen; judged=$sha; }
        grep -qx "$sha" <<< "$unjudged" || continue
        pr=$(git show -s --format=%s "$sha" | sed -n 's/.*(#\([0-9]*\))$/#\1/p')
        case "$verdict" in
            pending) echo "guard: ${sha:0:8} ($pr) landed from Linux; its macOS run has no verdict yet" ;;
            green) judge "$sha" success 'green on macOS after a Linux landing'; echo "guard: ${sha:0:8} ($pr) is green on macOS" ;;
            red*)
                if [ "$sha" = "$tip" ] && [ "$judged" = "$sha" ] \
                    && { [ "$(landed_from_of "$sha^")" != linux ] || [ "$(followup "$sha^")" = success ]; } \
                    && attempt auto_revert "$sha" "${verdict#red }" && [ "$status" -eq 0 ]; then
                    echo "guard: ${sha:0:8} ($pr) was red on macOS and is reverted"
                else
                    judge "$sha" failure 'red on macOS; reported, not reverted'
                    tell_keeper "$pr landed from Linux as ${sha:0:8} and main is red on macOS: ${verdict#red }. Not reverted: it is not the only change since the last green main, or the revert failed."
                fi ;;
        esac
    done
}
refresh_upstream() {
    git fetch -q upstream main || refuse 'cannot refresh upstream main'
}
squash_message() {
    local title=$pr_title
    [[ "$title" == Notchcast:* ]] || title="Notchcast: $title"
    printf '%s (#%s)\n' "$title" "$pr"
    if printf '%s\n' "$title" | grep -Eiq '^(notchcast: )?fix '; then
        printf '\n'
        grep -E '^No test: [^[:space:]].*' <<< "$pr_body" || true
    fi
    if [ -n "$drift_signoff" ]; then printf '\n%s\n' "$drift_signoff"; fi
}
# Runs "$@" in a subshell with errexit on, so its refuse ends one PR, not the run; leaves the exit code in status.
attempt() {
    set +e
    (set -e; "$@")
    status=$?
    set -e
}
# Takes PR $1 off the train; $2 says why unless the refusal above did. The last PR's reason is the run's refusal.
drop() {
    local pr kept=()
    [ -z "$covered" ] || refuse "train ${train_run:0:8}: #$1 ${2:-refused above}; nothing lands on that run: run notchcast/train.sh again"
    if [ ${#train[@]} -eq 1 ]; then
        [ -z "${2:-}" ] || refuse "$2"
        exit 1
    fi
    echo "DROPPED #$1: ${2:-refused above}; the train goes on without it" >&2
    for pr in "${train[@]}"; do
        [ "$pr" = "$1" ] || kept+=("$pr")
    done
    train=("${kept[@]}")
    rerun=1
}
green() { [ "$(check_run "$1" build)" = success ] || local_build_green "$1"; }
# The gates PR $1 passes before it is merged: open, ready, and its checks green on its exact head.
admit() {
    local pr=$1 metadata head name verdict required branch generated proven sha
    metadata=$(gh pr view "$pr" -R "$FORK_REPO" --json state,isDraft,labels,headRefOid,headRefName,baseRefName,isCrossRepository,title,body)
    [ "$(jq -r .baseRefName <<< "$metadata")" = main ] || refuse 'PR base must be main'
    [ "$(jq -r .state <<< "$metadata")" = OPEN ] || refuse 'PR must be open and ready'
    if [ "$(jq -r .isDraft <<< "$metadata")" = true ]; then
        [ -n "$covered" ] || refuse 'PR must be open and ready; a draft lands only on a green train run'
        jq -e '(.labels // []) | any(.name == "land")' <<< "$metadata" > /dev/null \
            || refuse "draft #$pr has no land label, the lead's sign-off to land it on a train run"
    fi
    head=$(jq -r .headRefOid <<< "$metadata")
    git fetch origin main "refs/pull/$pr/head" '+refs/notchcast/synced/*:refs/notchcast/synced/*'
    git cat-file -e "$head^{commit}" || refuse 'PR head unavailable'
    if [ -n "$covered" ]; then
        [ "$head" = "$(< "$scratch/train-head-$pr")" ] || refuse "PR #$pr moved past the head train ${train_run:0:8} tested"
        printf '%s\n' "$metadata" > "$scratch/pr-$pr.json"
        return 0
    fi
    for name in design leaks; do
        verdict=$(check_run "$head" "$name")
        [ "$verdict" = none ] || [ "$verdict" = success ] || refuse "$name is $verdict on ${head:0:8}; wait for success"
    done
    branch=$(jq -r .headRefName <<< "$metadata")
    required=$(python3 notchcast/app-proof.py plan origin/main "$head")
    if [ -n "$required" ]; then
        verdict=$(check_run "$head" proof)
        [ "$verdict" = success ] || refuse "real-app proof ($required) is $verdict on ${head:0:8}; it runs on the PR, or: gh workflow run Proof --ref $branch -R $FORK_REPO"
    fi
    verdict=$(check_run "$head" build)
    if local_build_green "$head"; then verdict=success; fi
    [ "$verdict" = success ] || [ "$verdict" = none ] || [ "$verdict" = cancelled ] \
        || refuse "build is $verdict on ${head:0:8}: wait for it or fix it (cancel a pending one to use a green head that differs only in generated files)"
    if [ "$verdict" != success ]; then
        # A head that differs from a green head of this branch only in generated files needs no new build:
        # landing keeps main's copies of them (merge_onto), so the green build already proved what lands.
        generated=$(python3 -c 'from notchcast.ci import GENERATED; print("\n".join(GENERATED))')
        proven=
        for sha in $(git rev-list --max-count=30 "$head") $(gh run list -R "$FORK_REPO" -w PR -b "$branch" -L 30 --json headSha,conclusion \
                --jq '.[] | select(.conclusion == "success") | .headSha' | awk '!seen[$0]++'); do
            git fetch -q origin "$sha" 2>/dev/null && green "$sha" || continue
            [ -n "$(git diff --name-only "$sha" "$head" | grep -vxF "$generated")" ] || { proven=$sha; break; }
        done
        [ -n "$proven" ] || refuse "build is not green on ${head:0:8}; if it has none, run: gh workflow run PR --ref $branch -R $FORK_REPO -f hosted=true"
        echo "build: ${head:0:8} differs from green ${proven:0:8} only in generated files"
    fi
    printf '%s\n' "$metadata" > "$scratch/pr-$pr.json"
}
uncovered() { echo "train: ${train_run:0:8} $1; each PR's own head checks decide" >&2; }
# Sets covered when $train_run is a green train.sh merge of current main and each PR's current head.
covered=
train_covers() {
    local commit i=${#train[@]} pr head parents name verdict required
    git fetch -q origin main '+refs/heads/train/*:refs/remotes/origin/train/*'
    train_run=$(git rev-parse --verify -q "$train_run^{commit}") || { uncovered 'is not on origin'; return 0; }
    commit=$train_run
    while [ "$i" -gt 0 ]; do
        i=$((i - 1))
        pr=${train[$i]}
        head=$(gh pr view "$pr" -R "$FORK_REPO" --json headRefOid --jq .headRefOid)
        parents=($(git rev-list --no-walk --parents "$commit"))
        [ ${#parents[@]} -eq 3 ] && [ "${parents[2]}" = "$head" ] \
            || { uncovered "does not merge #$pr's head ${head:0:8} as PR $((i + 1))"; return 0; }
        echo "$head" > "$scratch/train-head-$pr"
        commit=${parents[1]}
    done
    [ "$commit" = "$(git rev-parse origin/main)" ] || { uncovered "is built on ${commit:0:8}, not current main"; return 0; }
    for name in build design leaks; do
        verdict=$(check_run "$train_run" "$name")
        [ "$verdict" = success ] || { uncovered "has $name $verdict"; return 0; }
    done
    required=$(python3 notchcast/app-proof.py plan origin/main "$train_run")
    if [ -n "$required" ]; then
        verdict=$(check_run "$train_run" proof)
        [ "$verdict" = success ] || { uncovered "has real-app proof ($required) $verdict"; return 0; }
    fi
    train_base=$commit
    covered=1
    echo "train: ${train_run:0:8} is green on main ${commit:0:8} plus the current head of #${train[*]}"
}
# Sets the globals merge_onto and squash_message read from what admit (or --check) saved for PR $1.
load() {
    pr=$1
    metadata=$(< "$scratch/pr-$pr.json")
    head=$(jq -r .headRefOid <<< "$metadata")
    pr_title=$(jq -r '.title // ""' <<< "$metadata")
    pr_body=$(jq -r '.body // ""' <<< "$metadata")
}
# A fresh scratch tree at commit $1, with the shell in it.
tree_at() {
    cd "$top"
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    git worktree add --quiet --detach "$scratch/tree" "$1"
    cd "$scratch/tree"
}
top=$(pwd)
scratch=$(mktemp -d)
cleanup() {
    local code=$?
    cd "$top"  # out of the scratch tree before it goes
    git worktree remove --force "$scratch/base" >/dev/null 2>&1 || true
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    rm -rf "$scratch"
    remove_tools
    # Bash 3.2 runs this with status 0 after an unbound-variable abort, so only a finished run exits 0.
    [ "$code" -ne 0 ] || [ -n "${finished:-}" ] || code=1
    exit "$code"
}
trap cleanup EXIT
mkdir "$scratch/tmp"
check=0
train_run=
if [ "${1:-}" = --train-run ] && [ "$#" -ge 3 ]; then
    train_run=$2
    shift 2
fi
if [ "${1:-}" = --guard ] && [ -z "$train_run" ] && [ "$#" -eq 1 ]; then
    guard
    finished=1
    exit 0
elif [ "${1:-}" = --check ] && [ -z "$train_run" ] && [ "$#" -eq 3 ]; then
    check=1
    base=$(git rev-parse --verify "$2^{commit}")
    head=$(git rev-parse --verify "$3^{commit}")
    # The head commit stands in for the PR.
    jq -n --arg head "$head" --arg title "$(git show -s --format=%s "$head")" --arg body "$(git show -s --format=%b "$head")" \
        '{headRefOid: $head, title: $title, body: $body}' > "$scratch/pr-check.json"
    train=(check)
elif [ "$#" -ge 1 ] && [[ "$*" =~ ^[0-9]+(\ [0-9]+)*$ ]]; then
    repeated=$(printf '%s\n' "$@" | sort | uniq -d | paste -sd' ' -)
    [ -z "$repeated" ] || refuse "PR named more than once: $repeated"
    hold_claim "$@"
    train=("$@")
    if [ -n "$hold_pr" ] && [ "$#" -gt 1 ]; then
        echo "landing is held for #$hold_pr: the train is cut to it" >&2
        train=("$hold_pr")
    fi
    hold_owner=${hold_pr:-$1}
    # Before anything lands on top of it: an earlier Linux landing that went red on macOS is still revertible.
    attempt guard
    [ "$status" -eq 0 ] || echo 'WARN: the Linux-landing guard failed; run notchcast/land.sh --guard' >&2
    [ -z "$train_run" ] || train_covers
    for pr in "${train[@]}"; do
        attempt admit "$pr"
        [ "$status" -eq 0 ] || drop "$pr"
    done
    base=$(git rev-parse origin/main)
    [ -z "$covered" ] || [ "$base" = "$train_base" ] || refuse "main moved past train ${train_run:0:8}'s base; run notchcast/train.sh again"
else
    refuse 'usage: land.sh [--train-run <sha>] <pr>... | --check <base-ref> <head-ref> | --guard'
fi
# Squash here, not on GitHub: GitHub ignores .gitattributes merge=union and calls union-only overlaps conflicts.
# Merges PR $2 onto $1 and leaves its squash commit, whose only parent is $1, in $scratch/commit-$2.
squash_onto() {
    load "$2"
    merge_onto "$1"
    squash_message > "$scratch/message"
    [ "$check" -eq 1 ] || notchcast/check-identity.sh message "$scratch/message" || refuse 'commit message names something private'
    cp "$scratch/message" "$scratch/message-$2"
    as_maintainer git commit-tree "HEAD^{tree}" -p "$1" -F "$scratch/message" > "$scratch/commit-$2"
}
# Rewrites the chain with the trailer saying where its harness proof ran. That is the landing log
# (git log --grep '^Landed-from: linux'), and what --guard follows up.
stamp() {
    local pr parent=$base
    for pr in "${train[@]}"; do
        { cat "$scratch/message-$pr"; printf '\nLanded-from: %s\n' "$landed_from"; } > "$scratch/message"
        as_maintainer git commit-tree "$(< "$scratch/commit-$pr")^{tree}" -p "$parent" -F "$scratch/message" > "$scratch/commit-$pr"
        parent=$(< "$scratch/commit-$pr")
    done
    tip=$parent
}
# Stacks the train on $base, each PR squashed onto the one before it; a PR that refuses is dropped. Checks out tip.
build_chain() {
    local pr
    cd "$top"
    refresh_upstream
    tip=$base
    for pr in "${train[@]}"; do
        [ ${#train[@]} -eq 1 ] || echo "train: #$pr onto ${tip:0:8}"
        attempt squash_onto "$tip" "$pr"
        if [ "$status" -eq 0 ]; then tip=$(< "$scratch/commit-$pr"); else drop "$pr"; fi
    done
    tree_at "$tip"
}
# The fork queue filter runs the selected names in one parallel pass. Sets failed.
run_harnesses() {
    local name file status=0
    failed=
    [ "$#" -gt 0 ] || return 0
    rm -rf "$scratch/tmp"
    mkdir "$scratch/tmp"
    NOTCHCAST_ONLY_TESTS="$*" TMPDIR="$scratch/tmp" TINYCAST_TEST_JOBS="${CHAD_BUILD_QUEUE_JOBS:-4}" ./Scripts/run-tests.sh || status=$?
    for name in "$@"; do
        [ -e "$(echo "$scratch"/tmp/tinycast-harness*/"$name.log")" ] || refuse "$name is selected but run-tests.sh does not run it"
    done
    for file in "$scratch"/tmp/tinycast-harness*/*.failed; do
        [ ! -e "$file" ] || failed="$failed${failed:+ }$(basename "$file" .failed)"
    done
    [ "$status" -eq 0 ] || [ -n "$failed" ] || refuse 'the harness run failed without naming a harness'
}
# Sets proof, and left to the selected harnesses it excused, from the isolated runner's build of this tree if there
# is one. Refuses a toolchain other than ISOLATED_TOOLCHAIN, and an excused harness that only a hosted run proves.
isolated_proof() {
    local found url stamp excused need
    found=$(python3 "$(dirname "$selector")/ci.py" isolated-proof HEAD) || found=
    [ -n "$found" ] || return 0
    { read -r url; read -r stamp; read -r excused || true; } <<< "$found"
    [ "$stamp" = "$ISOLATED_TOOLCHAIN" ] \
        || refuse "the isolated run $url tested this tree with '$stamp', and landing expects '$ISOLATED_TOOLCHAIN' (ISOLATED_TOOLCHAIN, notchcast/config.env): land on a hosted train (NOTCHCAST_TRAIN_MAC=hosted notchcast/train.sh ${train[*]})"
    left=$(grep -xF -f <(tr ' ' '\n' <<< "$excused") "$scratch/selected" || true)
    need=$(grep -xF -f <(tr ' ' '\n' <<< "$HOSTED_ONLY_TESTS") <<< "$left" | grep -vxF -f <(tr ' ' '\n' <<< "$CI_SKIP_TESTS") | paste -sd' ' - || true)
    [ -z "$need" ] \
        || refuse "the isolated run $url did not prove $need (red there and on upstream), and only a hosted run can: NOTCHCAST_TRAIN_MAC=hosted notchcast/train.sh ${train[*]}"
    proof=$url
    isolated=1
}
# One pass on the tree at HEAD over the union of what each squash in $base..HEAD selects. Sets failed.
# Not covered without an Xcode build of this tree: code no selected harness compiles (UI, AppCore wiring,
# resources); the PR build covered each head alone, and Sync and Snapshot follow on main.
harnesses() {
    local commit proof= names why tested= unproven= skipped isolated= left=
    : > "$scratch/linux"
    for commit in $(git rev-list --reverse "$base..HEAD"); do
        if [ "$platform" = linux ]; then
            TMPDIR="$scratch/tmp" "$selector" --linux "$scratch/linux-one" "$commit^" "$commit"
            cat "$scratch/linux-one" >> "$scratch/linux"
        else
            TMPDIR="$scratch/tmp" "$selector" "$commit^" "$commit"
        fi
    done | sort -u > "$scratch/selected"
    [ -s "$scratch/selected" ] || refuse 'no harness selected for the merged tree'
    names=$(< "$scratch/selected")
    landed_from=mac
    # run-tests.sh skips these here (test-harnesses.sh), so only a hosted run of this exact tree proves them;
    # a Linux landing never proves one itself, whatever runner it is on.
    { [ "$platform" = mac ] && { [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] || [ "${NOTCHCAST_ISOLATED_RUNNER:-}" = 1 ]; }; } \
        || unproven=$(grep -xF -f <(tr ' ' '\n' <<< "$HOSTED_ONLY_TESTS") "$scratch/selected" | paste -sd' ' - || true)
    [ "$check" -eq 1 ] || proof=$(python3 "$(dirname "$selector")/ci.py" tested-run HEAD) || proof=
    [ "$check" -eq 1 ] || [ -n "$proof" ] || isolated_proof
    [ -z "$unproven" ] || [ "$check" -eq 1 ] || [ -n "$proof" ] \
        || refuse "hosted-only harnesses are selected and no hosted run tested this tree: $unproven; this machine never runs them (HOSTED_ONLY_TESTS, notchcast/config.env): land on a train run that ran hosted (notchcast/train.sh ${train[*]})"
    # A covered train run tested this exact tree on GitHub; only the harnesses its hosted runner skips are left.
    if [ -n "$covered" ]; then
        echo "harnesses: covered by train ${train_run:0:8} (tree identical); running only what its runner skips"
        names=$(grep -xF -f <(tr ' ' '\n' <<< "$CI_SKIP_TESTS") "$scratch/selected" || true)
        tested=1
    elif [ -n "$proof" ]; then
        echo "harnesses: $proof built and tested this tree; running only what its runner skips"
        names=$(grep -xF -f <(tr ' ' '\n' <<< "$CI_SKIP_TESTS") "$scratch/selected" || true)
        tested=1
    fi
    # The isolated runner skips nothing: only what it excused is left, to run here or stay unproven as below.
    if [ -n "$isolated" ]; then
        echo "harnesses: the isolated run $proof proved all of them but ${left:-none}"
        names=$left
    fi
    if [ "$platform" = linux ] && [ -n "$tested" ]; then
        # A macOS runner tested this tree; only what it skips is left, and that needs a Mac.
        [ -z "$names" ] || route "the hosted run skipped $(echo $names), which run only on a Mac"
    elif [ "$platform" = linux ]; then
        why=$(sort -u "$scratch/linux" | awk -F': ' '$1 != kind { printf "%s%s:", (NR > 1 ? "; " : ""), $1; kind = $1 } { printf " %s", $2 }')
        [ -z "$why" ] || route "$why"
        names=$(grep -xF -f <(tr ' ' '\n' <<< "$LINUX_OK_TESTS") "$scratch/selected" || true)
        landed_from=linux
        echo "harnesses: every harness this diff reaches is linux-ok; proving it here on $(echo $names | wc -w | tr -d ' ') of them"
    fi
    skipped=$(grep -xF -f <(tr ' ' '\n' <<< "$unproven") <<< "$names" | paste -sd' ' - || true)
    if [ -n "$skipped" ]; then
        echo "SKIPPED, proven by no run: $skipped (hosted-only, HOSTED_ONLY_TESTS in notchcast/config.env)"
        names=$(grep -vxF -f <(tr ' ' '\n' <<< "$skipped") <<< "$names" || true)
    fi
    run_harnesses $names
}
# Runs those of the harnesses $2 that exist at commit $1 on its tree. Sets failed.
harnesses_at() {
    local name names=
    tree_at "$1"
    for name in $2; do
        [ ! -e "Tests/$name.swift" ] || names="$names $name"
    done
    run_harnesses $names
}
# Sets breaker to the first PR whose squash turns the harnesses $1 red, by halving; refuses if main is red too.
breaking_pr() {
    local low=0 high=$((${#train[@]} - 1)) mid
    while [ "$low" -lt "$high" ]; do
        mid=$(((low + high) / 2))
        echo "bisecting: $1 on the train up to #${train[$mid]}"
        harnesses_at "$(< "$scratch/commit-${train[$mid]}")" "$1"
        if [ -n "$failed" ]; then high=$mid; else low=$((mid + 1)); fi
    done
    breaker=${train[$low]}
    [ "$low" -eq 0 ] || return 0
    echo "bisecting: $1 on main ${base:0:8}"
    harnesses_at "$base" "$1"
    [ -z "$failed" ] || refuse "main is red: $failed"
}
rerun=1
pushes=0
while :; do
    build_chain
    [ -z "$covered" ] || [ "$(git rev-parse 'HEAD^{tree}')" = "$(git rev-parse "$train_run^{tree}")" ] \
        || refuse "the merged tree is not the tree train ${train_run:0:8} tested"
    if [ "$rerun" -eq 1 ]; then
        harnesses
        if [ -n "$failed" ]; then
            red=$failed
            # Bisect reruns them alone, so one red only under load would be blamed on the last PR.
            run_harnesses $red
            alone=passes
            [[ "$red" != *' '* ]] || alone=pass
            [ -n "$failed" ] || refuse "$red failed in the full pass but $alone alone on the merged tree: a load-only flake, or a PR on this train breaks it only under load, so no PR is dropped; fix the harness, run land.sh again, or land fewer PRs to find it"
            red=$failed
            breaking_pr "$red"
            drop "$breaker" "$red failed"
            continue
        fi
        echo 'PASS: merged-tree harnesses'
        rerun=0
    fi
    [ "$check" -eq 0 ] || { finished=1; exit 0; }
    wait_for_sync
    for pr in "${train[@]}"; do
        load "$pr"
        [ "$(gh pr view "$pr" -R "$FORK_REPO" --json headRefOid --jq .headRefOid)" = "$head" ] \
            || drop "$pr" "PR #$pr moved past ${head:0:8} during the check; run land.sh $pr again"
    done
    [ "$rerun" -eq 0 ] || continue
    hold_renew_claimed
    check_hold "$hold_owner"  # a hold set while the harnesses ran wins
    stamp
    # The chain's first parent is $base, so this plain (never forced) push lands only while main is still $base.
    if git push origin "$tip:refs/heads/main"; then break; fi
    [ -z "$covered" ] || refuse "main moved past train ${train_run:0:8}'s base; run notchcast/train.sh again"
    pushes=$((pushes + 1))
    [ "$pushes" -lt 6 ] || refuse "main moved during each of 6 pushes; run land.sh ${train[*]} again"
    git fetch --quiet origin main '+refs/notchcast/synced/*:refs/notchcast/synced/*'
    moved_to=$(git rev-parse origin/main)
    [ "$moved_to" != "$base" ] || refuse "push to main failed and main did not move from ${base:0:8}"
    previous=$base
    base=$moved_to
    # Trees, not the commit range: a Sync rewrite of main changes real files and still reruns.
    moved=$(git diff --name-only "$previous" "$base") || refuse 'cannot read how main moved'
    if [ -z "$(grep -vxF -f <(python3 -c 'from notchcast.ci import GENERATED; print("\n".join(GENERATED))') <<< "$moved" || true)" ]; then
        echo "main moved ${previous:0:8} -> ${base:0:8} only in generated files; merging again without rerunning harnesses"
    else
        echo "main moved ${previous:0:8} -> ${base:0:8}; merging again and rerunning harnesses"
        rerun=1
    fi
done
unclosed=
parent=$base
for pr in "${train[@]}"; do
    load "$pr"
    commit=$(< "$scratch/commit-$pr")
    if gh pr close "$pr" -R "$FORK_REPO" --comment "Landed on main as $commit by notchcast/land.sh: squash of $head onto $parent."; then
        delete_head "$(jq -r .headRefName <<< "$metadata")" "$head" "$(jq -r .isCrossRepository <<< "$metadata")"
    else
        unclosed="$unclosed #$pr"
    fi
    parent=$commit
done
if [ -n "$covered" ]; then
    for name in $(git for-each-ref --points-at "$train_run" --format='%(refname:lstrip=3)' refs/remotes/origin/train/); do
        delete_head "$name" "$train_run"
    done
fi
if [ "$landed_from" = linux ]; then
    echo "LANDED from Linux as ${tip:0:8}: Snapshot now runs the macOS suite on it; notchcast/land.sh --guard (and every later landing) reverts it if that run is red"
fi
[ -z "$unclosed" ] || refuse "landed on main as $tip, but closing$unclosed failed: close by hand, do not rerun land.sh"
finished=1
