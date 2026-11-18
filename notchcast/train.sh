#!/bin/bash
# One CI run for a whole train of PRs, split in halves while red; --queue picks the train and lands what is green.
# notchcast/README.md has the rules.
set -euo pipefail
[ "$*" = --queue ] || { [ "$#" -ge 1 ] && [[ "$*" =~ ^[0-9]+(\ [0-9]+)*$ ]]; } \
    || { echo 'usage: train.sh <pr> <pr>... | --queue' >&2; exit 2; }
repeated=$(printf '%s\n' "$@" | sort | uniq -d | paste -sd' ' -)
[ -z "$repeated" ] || { echo "REFUSED: PR named more than once: $repeated" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"
top=$(pwd)
source notchcast/config.env
source notchcast/merge.sh
refuse() { echo "REFUSED: $*" >&2; exit 1; }
poll=${NOTCHCAST_TRAIN_POLL:-60}
scratch=$(mktemp -d)
# Lines "<branch> <sha>": trains pushed that have no verdict yet, scrapped if this script stops early.
unsettled="$scratch/unsettled"
: > "$unsettled"
settle() { grep -v "^$1 " "$unsettled" > "$scratch/settled" || true; mv "$scratch/settled" "$unsettled"; }
# Cancels the unfinished dispatched runs of branch $1 at $2 and deletes the branch.
scrap_train() {
    gh run list -R "$FORK_REPO" -b "$1" -e workflow_dispatch --json databaseId,status,headSha \
        --jq ".[] | select(.headSha == \"$2\" and .status != \"completed\") | .databaseId" |
        while read -r run; do gh run cancel "$run" -R "$FORK_REPO" >/dev/null || true; done
    git -C "$top" push -q origin --delete "$1" || echo "WARN: could not delete $1" >&2
    settle "$1"
}
cleanup() {
    local branch sha
    cd "$top"
    while read -r branch sha; do
        echo "train: scrapping $branch, which has no verdict" >&2
        scrap_train "$branch" "$sha"
    done < <(cat "$unsettled")
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    rm -rf "$scratch"
}
trap cleanup EXIT
tree_at() {
    cd "$top"
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    git worktree add --quiet --detach "$scratch/tree" "$1"
    cd "$scratch/tree"
}
train_branch() { echo "train/$(IFS=-; echo "$*")"; }
# Merges PR $2 onto $1 and leaves the merge commit in $scratch/tip.
stack() {
    local metadata
    metadata=$(gh pr view "$2" -R "$FORK_REPO" --json state,headRefOid,baseRefName,title,body)
    [ "$(jq -r '.state + " " + .baseRefName' <<< "$metadata")" = 'OPEN main' ] || refuse "#$2 must be open against main"
    head=$(jq -r .headRefOid <<< "$metadata")
    pr_title=$(jq -r '.title // ""' <<< "$metadata")
    pr_body=$(jq -r '.body // ""' <<< "$metadata")
    git -C "$top" fetch -q origin "refs/pull/$2/head"
    echo "train: #$2 ${head:0:8} onto ${1:0:8}" >&2
    merge_onto "$1" >&2
    git rev-parse HEAD > "$scratch/tip"
}
# Merges PRs $2... onto $1 into $tip and sets stacked to the PRs that merged. One that refuses is dropped and told
# why in a PR comment (a conflict names the earlier PR of the train that touched the file), and the rest goes on.
build_train() {
    local pr code reason blocker other commit
    tip=$1
    stacked=
    : > "$scratch/merges"
    shift
    for pr in "$@"; do
        # A subshell with its own errexit, so a refusal ends this PR and not the run.
        set +e
        (set -e; stack "$tip" "$pr") 2> "$scratch/refusal"
        code=$?
        set -e
        cat "$scratch/refusal" >&2
        cd "$top"
        if [ "$code" -eq 0 ]; then
            tip=$(< "$scratch/tip")
            [ "$(git rev-parse "$tip^{commit}")" = "$tip" ] || refuse "train tip is not a commit: $tip"
            echo "$pr $tip" >> "$scratch/merges"
            stacked="$stacked${stacked:+ }$pr"
            continue
        fi
        reason=$(sed -n 's/^REFUSED: //p' "$scratch/refusal" | tail -1)
        if [[ "$reason" == 'merge conflict: '* ]]; then
            blocker=main
            while read -r other commit; do
                git diff --name-only "$commit^1" "$commit" | grep -qxF -f <(tr ' ' '\n' <<< "${reason#merge conflict: }") || continue
                blocker="#$other in the landing batch"
                break
            done < "$scratch/merges"
            reason="conflicts with $blocker; rebase on main"
        else
            reason="dropped from the landing batch: ${reason:-its merge onto main failed}"
        fi
        echo "DROPPED #$pr: $reason"
        gh pr comment "$pr" -R "$FORK_REPO" --body "$reason" >/dev/null || echo "WARN: could not comment on #$pr" >&2
    done
}
# Every one must finish green on the train's tip; all but Design take the train's base, as a PR run has it.
workflows='pr.yml proof.yml design.yml leaks.yml'
# Pushes $sha as new branch $branch and dispatches its workflows against base $1.
start_train() {
    local base=$1 file
    git push -q origin "$sha:refs/heads/$branch"
    echo "$branch $sha" >> "$unsettled"
    for file in $workflows; do
        if [ "$file" = design.yml ]; then
            gh workflow run "$file" -R "$FORK_REPO" --ref "$branch" >&2
        elif [ "$file" = pr.yml ]; then
            # A self-hosted Mac proves no tree, so a train's PR run must be hosted to count.
            gh workflow run "$file" -R "$FORK_REPO" --ref "$branch" -f "base=$base" -f hosted=true >&2
        else
            gh workflow run "$file" -R "$FORK_REPO" --ref "$branch" -f "base=$base" >&2
        fi
    done
}
# The dispatched run of workflow $1 on branch $2 at $3: pending, none, or its conclusion.
run_verdict() {
    gh run list -R "$FORK_REPO" -w "$1" -b "$2" -e workflow_dispatch -L 20 --json headSha,status,conclusion,createdAt \
        --jq "[.[] | select(.headSha == \"$3\")] | max_by(.createdAt) | if . == null then \"none\" elif .status != \"completed\" then \"pending\" else .conclusion end"
}
# Waits until each workflow on branch $1 at $2 is done; green when all are success, red at the first that is not,
# whose run is then in red_url.
wait_train() {
    local branch=$1 sha=$2 file verdict pending waited=0
    red_url=
    while :; do
        pending=
        for file in $workflows; do
            verdict=$(run_verdict "$file" "$branch" "$sha") || verdict=pending
            case "$verdict" in
                success) ;;
                pending) pending=1 ;;
                none) [ "$waited" -lt 900 ] || { echo "train: $file never started on $branch" >&2; return 1; }; pending=1 ;;
                *)
                    echo "train: $file is $verdict on $branch ${sha:0:8}" >&2
                    red_url=$(gh run list -R "$FORK_REPO" -w "$file" -b "$branch" -e workflow_dispatch -L 20 --json headSha,url,createdAt \
                        --jq "[.[] | select(.headSha == \"$sha\")] | max_by(.createdAt) | .url // empty") || red_url=
                    return 1 ;;
            esac
        done
        [ -n "$pending" ] || return 0
        sleep "$poll"
        waited=$((waited + poll))
    done
}
# When PR $1 was last marked ready or labelled land; nothing for a PR that was opened ready.
ready_since() {
    gh api "repos/$FORK_REPO/issues/$1/timeline" --paginate \
        --jq '.[] | select(.event == "ready_for_review" or (.event == "labeled" and .label.name == "land")) | .created_at' | tail -1
}
# The first LAND_BATCH_SIZE open PRs on main, oldest sign-off first. Signed off is ready, or a draft labelled land;
# its build must be green on its head (a draft may have none: the train run is its build). A PR a batch already
# found red alone waits for a new head.
pick_batch() {
    local pr draft head created verdict since
    gh pr list -R "$FORK_REPO" --state open --base main -L 200 --json number,isDraft,labels,headRefOid,createdAt,comments \
        --jq '.[] | . as $pr | select((.isDraft | not) or any(.labels[]; .name == "land"))
            | select(any(.comments[]; .body | contains("in the landing batch at head " + $pr.headRefOid)) | not)
            | "\(.number) \(.isDraft) \(.headRefOid) \(.createdAt)"' |
        while read -r pr draft head created; do
            verdict=$(check_run "$head" build)
            [ "$verdict" = success ] || { [ "$draft" = true ] && [ "$verdict" = none ]; } \
                || { echo "queue: #$pr waits, build is $verdict on ${head:0:8}" >&2; continue; }
            since=$(ready_since "$pr")
            echo "${since:-$created} $pr"
        done | sort | sed -n "1,${LAND_BATCH_SIZE}p" | cut -d' ' -f2 | paste -sd' ' -
}
# The one place a batch lands. A batch whose union needs no Mac (#1033's linux-ok) plugs its Linux landing in here.
land_batch() { bash notchcast/land.sh --train-run "$@"; }
auto=
if [ "$*" = --queue ]; then
    auto=1
    picked=$(pick_batch)
    [ -n "$picked" ] || { echo 'queue: no open PR on main is signed off and green on its head'; exit 0; }
    echo "queue: batch $picked"
    set -- $picked
fi
status=0
# Landing squashes each PR, so a PR that holds another's commits can conflict with main once that one lands, though
# the train merges both heads cleanly. A train of such a pair is refused; --queue leaves the holder out and tells it.
git fetch -q origin main '+refs/notchcast/synced/*:refs/notchcast/synced/*'
# PR $1 holds PR $2 when its head reaches a commit on $2's own first-parent line; a branch both merged is on neither.
holds() { [ -n "$(comm -12 "$scratch/all-$1" "$scratch/line-$2")" ]; }
clear=
for pr in "$@"; do
    git fetch -q origin "refs/pull/$pr/head"
    git rev-parse FETCH_HEAD > "$scratch/head-$pr"
    git rev-list FETCH_HEAD --not origin/main --glob=refs/notchcast/synced/ | sort > "$scratch/all-$pr"
    git rev-list --first-parent FETCH_HEAD --not origin/main --glob=refs/notchcast/synced/ | sort > "$scratch/line-$pr"
    kept=
    out=
    for other in $clear; do
        if [ -n "$out" ]; then
            holder=
        elif holds "$pr" "$other"; then
            holder=$pr
            # Both lines share commits when one PR was cut from the other: the one cut later is the holder.
            ! holds "$other" "$pr" || ! git merge-base --is-ancestor "$(< "$scratch/head-$pr")" "$(< "$scratch/head-$other")" || holder=$other
        elif holds "$other" "$pr"; then
            holder=$other
        else
            holder=
        fi
        if [ -z "$holder" ]; then
            kept="$kept $other"
            continue
        fi
        first=$other
        [ "$holder" = "$pr" ] || first=$pr
        reason="#$holder contains commits of #$first, and landing squashes each PR, so #$holder can conflict with main once #$first lands. Land #$first first, then merge main into #$holder."
        [ -n "$auto" ] || refuse "$reason"
        status=1
        echo "DROPPED #$holder: $reason"
        note="Left out of the landing batch at its head $(< "$scratch/head-$holder"): $reason"
        gh pr view "$holder" -R "$FORK_REPO" --json comments | jq -e --arg note "$note" 'any(.comments[]; .body == $note)' >/dev/null \
            || gh pr comment "$holder" -R "$FORK_REPO" --body "$note" >/dev/null || echo "WARN: could not comment on #$holder" >&2
        [ "$holder" = "$other" ] || { out=1; kept="$kept $other"; }
    done
    clear=$kept
    [ -n "$out" ] || clear="$clear $pr"
done
set -- $clear
queue=("$*")
while [ ${#queue[@]} -gt 0 ]; do
    git fetch -q origin main '+refs/notchcast/synced/*:refs/notchcast/synced/*'
    git fetch -q upstream main || refuse 'cannot refresh upstream main'
    base=$(git rev-parse origin/main)
    echo "open PRs: $(gh pr list -R "$FORK_REPO" --state open -L 200 --json number -q length || echo '?')/25"
    built=()
    for train in "${queue[@]}"; do
        build_train "$base" $train
        [ "$stacked" = "$train" ] || status=1
        [ -n "$stacked" ] || continue
        branch=$(train_branch $stacked)
        [ -z "$(git ls-remote origin "refs/heads/$branch")" ] \
            || refuse "origin already has $branch; land it or delete it: git push origin --delete $branch"
        built+=("$branch $tip $stacked")
    done
    queue=()
    [ ${#built[@]} -gt 0 ] || break
    for entry in "${built[@]}"; do
        read -r branch sha train <<< "$entry"
        start_train "$base"
    done
    landed=
    for entry in "${built[@]}"; do
        read -r branch sha train <<< "$entry"
        if wait_train "$branch" "$sha"; then
            if [ -n "$landed" ]; then
                echo "STALE $branch: green on main ${base:0:8}, which #$landed has moved; running it again"
                scrap_train "$branch" "$sha"
                queue+=("$train")
                continue
            fi
            settle "$branch"
            echo "GREEN $branch ${sha:0:8} on main ${base:0:8}: notchcast/land.sh --train-run $sha $train"
            [ -n "$auto" ] || continue
            if land_batch "$sha" $train; then
                landed=$train
                echo "LANDED #$train"
            else
                status=1
                echo "NOT LANDED #$train: land.sh refused above; its train branch $branch stays"
            fi
            continue
        fi
        status=1
        scrap_train "$branch" "$sha"
        set -- $train
        if [ "$#" -eq 1 ]; then
            echo "RED #$1 alone on main ${base:0:8}"
            echo "CULPRIT #$1 ${red_url:-no run started}"
            gh pr comment "$1" -R "$FORK_REPO" >/dev/null \
                --body "Red alone on main ${base:0:8} in the landing batch at head $(git rev-parse "$sha^2"): ${red_url:-no run started}" \
                || echo "WARN: could not comment on #$1" >&2
        else
            half=$((($# + 1) / 2))
            echo "RED $branch: splitting into ${*:1:half} | ${*:half+1}"
            queue+=("${*:1:half}" "${*:half+1}")
        fi
    done
done
exit "$status"
