#!/bin/bash
# One CI run for a whole train of PRs, split in halves while red; --queue picks the train and lands what is green.
# notchcast/README.md has the rules.
set -euo pipefail
detach=
[ "${1:-}" != --detach ] || { detach=1; shift; }
[ "$*" = --queue ] || { [ "$#" -ge 1 ] && [[ "$*" =~ ^[0-9]+(\ [0-9]+)*$ ]]; } \
    || { echo 'usage: train.sh [--detach] <pr> <pr>... | [--detach] --queue' >&2; exit 2; }
repeated=$(printf '%s\n' "$@" | sort | uniq -d | paste -sd' ' -)
[ -z "$repeated" ] || { echo "REFUSED: PR named more than once: $repeated" >&2; exit 1; }
[ ! -f "$HOME/.config/notchcast/private.env" ] || source "$HOME/.config/notchcast/private.env"
source "$(dirname "$0")/hold.sh"
land_lease
# The detached run has no terminal, so a force would not reach it.
[ -z "$detach" ] || [ -z "$land_forced" ] || { echo 'REFUSED: a forced train runs attached: drop --detach' >&2; exit 1; }
if [ -n "$detach" ]; then
    log="$(cd "$(git rev-parse --git-common-dir)" && pwd)/train-$(date +%Y%m%d-%H%M%S)-$$.log"
    # A new session outlives the chat or terminal that started it; the log ends with "train: exit <status>".
    python3 -c 'import os, sys
if os.fork(): sys.exit(0)
os.setsid()
os.execvp("bash", ["bash", *sys.argv[1:]])' "$0" "$@" > "$log" 2>&1 < /dev/null
    echo "train: detached, log $log"
    exit 0
fi
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
    # The branch goes first: it is what a stop halfway would leave behind for good.
    git -C "$top" push -q origin --delete "$1" || echo "WARN: could not delete $1" >&2
    gh run list -R "$FORK_REPO" -b "$1" -e workflow_dispatch --json databaseId,status,headSha \
        --jq ".[] | select(.headSha == \"$2\" and .status != \"completed\") | .databaseId" |
        while read -r run; do gh run cancel "$run" -R "$FORK_REPO" >/dev/null || true; done \
        || echo "WARN: could not cancel the runs of $1" >&2
    settle "$1"
}
cleanup() {
    local code=$? branch sha
    # A second stop signal or a failing step must not cut the scrap short.
    trap '' INT TERM HUP
    set +e
    cd "$top"
    while read -r branch sha; do
        echo "train: scrapping $branch, which has no verdict" >&2
        scrap_train "$branch" "$sha"
    done < <(cat "$unsettled")
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    rm -rf "$scratch"
    echo "train: exit $code"
}
trap cleanup EXIT
# Named, so cleanup reports the signal's status rather than the status of the command it cut short.
sleeper=
stop() { [ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null || true; exit "$1"; }
trap 'stop 129' HUP
trap 'stop 130' INT
trap 'stop 143' TERM
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
    metadata=$(gh pr view "$2" -R "$FORK_REPO" --json state,isDraft,labels,headRefOid,baseRefName,title,body)
    [ "$(jq -r '.state + " " + .baseRefName' <<< "$metadata")" = 'OPEN main' ] || refuse "#$2 must be open against main"
    head=$(jq -r .headRefOid <<< "$metadata")
    pr_title=$(jq -r '.title // ""' <<< "$metadata")
    pr_body=$(jq -r '.body // ""' <<< "$metadata")
    git -C "$top" fetch -q origin "refs/pull/$2/head"
    git -C "$top" rev-parse FETCH_HEAD > "$scratch/head-$2"  # the head it merges is the one a refusal record names
    echo "train: #$2 ${head:0:8} onto ${1:0:8}" >&2
    # The merge runs even for an unlabelled draft, so one pass names every reason a PR would be dropped for.
    set +e
    # land.sh squashes it with this message and refuses a private name in it, so the train refuses it first.
    (set -e; merge_onto "$1" >&2; pr=$2; squash_message > "$scratch/message"; check_message "$scratch/message" >&2)
    merged=$?
    set -e
    # land.sh refuses it after the Mac ran, and that loses the whole train.
    jq -e '(.isDraft | not) or any(.labels[]?; .name == "land")' <<< "$metadata" > /dev/null \
        || refuse "draft #$2 has no land label, the lead's sign-off to land it"
    [ "$merged" -eq 0 ] || exit 1
    git -C "$scratch/tree" rev-parse HEAD > "$scratch/tip"
}
# Merges PRs $2... onto $1 into $tip and sets stacked to the PRs that merged. One that refuses is dropped, and the
# rest goes on; tell_drops says why (a conflict names the earlier PR of the train that touched the file).
build_train() {
    local pr code reason files other commit conflict
    tip=$1
    stacked=
    : > "$scratch/merges"
    : > "$scratch/drops"
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
        reason=$(sed -n 's/^REFUSED: //p' "$scratch/refusal" | { grep -v '^merge conflict: ' || true; } | paste -sd';' - | sed 's/;/; /g')
        files=$(sed -n 's/^REFUSED: merge conflict: //p' "$scratch/refusal" | tail -1)
        if [ -n "$files" ]; then
            conflict="conflicts with main in $files: it waits for one merge round, which the landing owner starts when this PR is next to land; nobody merges main into it before that"
            while read -r other commit; do
                git diff --name-only "$commit^1" "$commit" | grep -qxF -f <(tr ' ' '\n' <<< "$files") || continue
                conflict="conflicts with #$other in the landing batch in $files: it rides a later train, after #$other lands; nobody merges main into it"
                break
            done < "$scratch/merges"
            reason="$conflict${reason:+; also: $reason}"
        else
            reason="dropped from the landing batch: ${reason:-its merge onto main failed}"
        fi
        printf '%s %s\n' "$pr" "$reason" >> "$scratch/drops"
    done
}
# Prints and comments the drops of the last build_train, the one the train keeps.
tell_drops() {
    local pr reason
    while read -r pr reason; do
        echo "DROPPED #$pr: $reason"
        gh pr comment "$pr" -R "$FORK_REPO" --body "$reason" >/dev/null || echo "WARN: could not comment on #$pr" >&2
    done < "$scratch/drops"
}
notify() {
    ! declare -F notchcast_notify >/dev/null || printf 'Notchcast: %s\n' "$1" | notchcast_notify || echo 'WARN: notify failed' >&2
}
# Every one must finish green on the train's tip; all but Design take the train's base, as a PR run has it.
workflows='pr.yml proof.yml design.yml leaks.yml'
# The ones with a Mac job, which take the train's lane as their hosted input (ready-check-test.py: GATED_JOBS).
mac_workflows='pr.yml proof.yml'
# A train's Mac jobs run on the isolated runner while NOTCHCAST_MAC_RUNNER names one (README, Runners), else hosted.
mac=hosted
label=$(gh variable get NOTCHCAST_MAC_RUNNER -R "$FORK_REPO" 2>/dev/null || true)
if [ "${NOTCHCAST_TRAIN_MAC:-}" != hosted ] && [ -n "$label" ]; then
    # A job for a label with no runner online stays queued for good, so such a train goes hosted.
    online=$(gh api "repos/$FORK_REPO/actions/runners" --jq '.runners[] | select(.status == "online") | .labels[].name' 2>/dev/null || true)
    if grep -qxF "$label" <<< "$online"; then mac=isolated; else echo "train: no runner labelled $label is online, so the Mac jobs are hosted"; fi
fi
# HOSTED_ONLY_TESTS of the tree in the current directory, every line that sets it.
hosted_only_list() { sed -n 's/^HOSTED_ONLY_TESTS="\(.*\)"$/\1/p' notchcast/config.env | paste -sd' ' -; }
# Before the push, for the train just built ($tip on $base, its merges in $scratch/merges): refuses one whose run
# land.sh could not find, and sets runner, where its Mac jobs go: hosted when only a hosted run proves it.
preflight() {
    local main_key tip_key commit pr changers='' hosted_only hosted_list
    tree_at "$base"
    main_key=$(python3 notchcast/ci.py tested-key "$tip")
    hosted_list=$(hosted_only_list)
    tree_at "$tip"
    tip_key=$(python3 notchcast/ci.py tested-key HEAD)
    hosted_list="$hosted_list $(hosted_only_list)"
    if [ "$main_key" != "$tip_key" ]; then
        while read -r pr commit; do
            git diff --quiet "$commit^1" "$commit" -- notchcast/ci.py || changers="$changers${changers:+ }#$pr"
        done < "$scratch/merges"
        refuse "the train's run would record tree ${tip_key:0:8}, but land.sh with main's ci.py looks for ${main_key:0:8}, so it could never land: ${changers:-a PR} changes ci.py tested-key; land that one first, alone (notchcast/land.sh <pr> on its own PR build), then train the rest"
    fi
    runner=$mac
    if ! (while read -r pr commit; do bash notchcast/changed-harnesses.sh "$commit^1" "$commit" > "$scratch/selected-$pr" || exit 1; done) < "$scratch/merges"; then
        cd "$top"
        [ "$mac" = isolated ] || return 0
        runner=hosted
        echo "train: changed-harnesses.sh failed, so no selection says the isolated runner may prove it, and its Mac jobs are hosted"
        return 0
    fi
    while read -r pr commit; do cat "$scratch/selected-$pr"; done < "$scratch/merges" > "$scratch/selected"
    cd "$top"
    [ "$mac" = isolated ] || return 0
    if [ -s "$scratch/hosted-prs" ] && cut -d' ' -f1 "$scratch/merges" | grep -qxF -f "$scratch/hosted-prs"; then
        runner=hosted
        echo "train: land.sh refused a PR of it for good on the isolated runner at its head, so its Mac jobs are hosted"
        return 0
    fi
    hosted_only=$(listed_in "$hosted_list" "$scratch/selected")
    [ -n "$hosted_only" ] || return 0
    runner=hosted
    echo "train: it selects hosted-only harnesses ($hosted_only), which land.sh trusts only from a hosted run, so its Mac jobs are hosted"
}
# Pushes $sha as new branch $branch and dispatches its workflows against base $1.
start_train() {
    local base=$1 file
    echo "train: $branch has its Mac jobs on the $runner runner" >&2
    echo "$branch $sha" >> "$unsettled"
    git push -q origin "$sha:refs/heads/$branch"
    for file in $workflows; do
        if [ "$file" = design.yml ]; then
            gh workflow run "$file" -R "$FORK_REPO" --ref "$branch" >&2
        elif [ "$runner" = hosted ] && [[ " $mac_workflows " == *" $file "* ]]; then
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
        # In the background: bash runs a trap only between foreground commands, and wait returns at a signal.
        sleep "$poll" &
        sleeper=$!
        wait "$sleeper"
        sleeper=
        waited=$((waited + poll))
    done
}
# When PR $1 was last labelled land, the lead's sign-off; marking it ready only gets it a PR build.
signed_off_since() {
    local at
    at=$(gh api "repos/$FORK_REPO/issues/$1/timeline" --paginate \
        --jq '.[] | select(.event == "labeled" and .label.name == "land") | .created_at' | tail -1) && [ -n "$at" ] \
        || { echo "queue: cannot read when #$1 was labelled land" >&2
            notify "the landing queue stopped: it cannot read when #$1 was labelled land" >&2; return 1; }
    echo "$at"
}
# The first LAND_BATCH_SIZE open PRs on main labelled land, ready or draft, oldest sign-off first. Its build must be
# green on its head; a draft's may be skipped or absent, since the train run is its build. A PR a batch already
# found red alone waits for a new head. While the newest sign-off of the batch is younger than LAND_SETTLE_SECONDS it
# prints only a "queue: waits" line, so PRs signed off close together ride one train.
pick_batch() {
    local pr draft head verdict since newest age
    : > "$scratch/heads"
    gh pr list -R "$FORK_REPO" --state open --base main -L 200 --json number,isDraft,labels,headRefOid,comments \
        --jq '.[] | . as $pr | select(any(.labels[]; .name == "land"))
            | select(any(.comments[]; .body | contains("in the landing batch at head " + $pr.headRefOid)) | not)
            | "\(.number) \(.isDraft) \(.headRefOid)"' |
        while read -r pr draft head; do
            echo "$pr@$head" >> "$scratch/heads"
            verdict=$(check_run "$head" build)
            [ "$verdict" = success ] || { [ "$draft" = true ] && [[ "$verdict" =~ ^(none|skipped)$ ]]; } \
                || { echo "queue: #$pr waits, build is $verdict on ${head:0:8}" >&2; continue; }
            since=$(signed_off_since "$pr") || exit 1
            echo "$since $pr"
        done | sort > "$scratch/signed" || return 1
    still_refused
    [ ! -s "$scratch/hosted-prs" ] \
        || echo "queue: #$(paste -sd' ' "$scratch/hosted-prs" | sed 's/ / #/g') train hosted: land.sh refused them for good on the isolated runner at these heads" >&2
    if [ -s "$scratch/refused-prs" ]; then
        echo "queue: #$(paste -sd' ' "$scratch/refused-prs" | sed 's/ / #/g') left out: land.sh refused them for good at these heads" >&2
        awk 'NR == FNR { out[$1]; next } !($2 in out)' "$scratch/refused-prs" "$scratch/signed" > "$scratch/kept"
        mv "$scratch/kept" "$scratch/signed"
    fi
    # Only the batch's own: sign-offs behind a full batch must not hold it back.
    newest=$(sed -n "1,${LAND_BATCH_SIZE}p" "$scratch/signed" | tail -1)
    if [ -n "$newest" ]; then
        age=$((${NOTCHCAST_NOW:-$(date +%s)} - $(jq -rn --arg at "${newest% *}" '$at | fromdateiso8601')))
        [ "$age" -ge "$LAND_SETTLE_SECONDS" ] || { echo "queue: waits, #${newest#* } signed off $age s ago"; return 0; }
    fi
    sed -n "1,${LAND_BATCH_SIZE}p" "$scratch/signed" | cut -d' ' -f2 | paste -sd' ' -
}
# Lines "<runner> <config> <pr>@<head>...": batches land.sh refused for good (exit 3) at those heads on a train whose
# Mac jobs ran on <runner>, under config.env blob <config>. Both such refusals judge an isolated runner's record, so a
# hosted train is the run that can change the verdict: the queue trains a batch refused on the isolated runner hosted,
# and leaves one refused on a hosted train out. Kept beside the detached train logs, so every tick's tree sees it.
refused_file="$(cd "$(git rev-parse --git-common-dir)" && pwd)/notchcast-refused"
config_key=$(git hash-object notchcast/config.env)
# Forgets each refusal under another config or with a head that moved (open PRs in $scratch/heads), and writes the
# PRs of the rest to $scratch/hosted-prs (refused on the isolated runner) or $scratch/refused-prs (refused hosted).
still_refused() {
    local runner key heads
    : > "$scratch/refusals"
    : > "$scratch/hosted-prs"
    : > "$scratch/refused-prs"
    [ -s "$refused_file" ] || return 0
    while read -r runner key heads; do
        [ "$key" = "$config_key" ] || continue
        ! tr ' ' '\n' <<< "$heads" | grep -qvxF -f "$scratch/heads" || continue
        echo "$runner $key $heads" >> "$scratch/refusals"
        if [ "$runner" = hosted ]; then
            tr ' ' '\n' <<< "$heads" | sed 's/@.*//' >> "$scratch/refused-prs"
        else
            tr ' ' '\n' <<< "$heads" | sed 's/@.*//' >> "$scratch/hosted-prs"
        fi
    done < "$refused_file"
    cat "$scratch/refusals" > "$refused_file"
}
# Batch $1 of train branch $2, its Mac jobs on runner $3, refused for good by the land.sh output in $scratch/landing:
# recorded at its heads, and told once, on each PR and to notchcast_notify.
refused_for_good() {
    local pr record='' reason next
    reason=$(sed -n 's/^REFUSED: //p' "$scratch/landing" | tail -1)
    for pr in $1; do record="$record${record:+ }$pr@$(< "$scratch/head-$pr")"; done
    echo "$3 $config_key $record" >> "$refused_file"
    next='the queue leaves these PRs out until one has a new head or config.env changes'
    [ "$3" = hosted ] || next='the queue trains these PRs hosted next, the run that can change that verdict'
    echo "REFUSED FOR GOOD #$1: its train branch $2 stays; $next"
    for pr in $1; do
        gh pr comment "$pr" -R "$FORK_REPO" >/dev/null \
            --body "Refused for good at its head $(< "$scratch/head-$pr"): land.sh refused the green train $2 (#${1// / #}) on the $3 runner: $reason. Next, $next." \
            || echo "WARN: could not comment on #$pr" >&2
    done
    notify "land.sh refused the green train $2 (#${1// / #}) for good on the $3 runner: $reason; $next"
}
# The one place a batch lands. A batch whose union needs no Mac (#1033's linux-ok) plugs its Linux landing in here.
land_batch() { bash notchcast/land.sh --train-run "$@"; }
auto=
if [ "$*" = --queue ]; then
    auto=1
    picked=$(pick_batch)
    [[ "$picked" != 'queue: waits'* ]] || { echo "$picked"; exit 0; }
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
        reason="#$holder contains commits of #$first, and landing squashes each PR, so #$holder can conflict with main once #$first lands. Land #$first first; then #$holder gets one merge round, which the landing owner starts when it is next to land."
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
    where=main
    if [ -n "${NOTCHCAST_TRAIN_ONTO:-}" ]; then
        # Built on a running train's tip, this one is proven by the time that one lands: land.sh compares trees.
        [ -z "$auto" ] || refuse 'a train built on another train never lands by itself; run it without --queue'
        git fetch -q origin '+refs/heads/train/*:refs/remotes/origin/train/*'
        base=$(git rev-parse --verify -q "$NOTCHCAST_TRAIN_ONTO^{commit}") || refuse "NOTCHCAST_TRAIN_ONTO $NOTCHCAST_TRAIN_ONTO is not a commit here"
        [ -n "$(git for-each-ref --points-at "$base" 'refs/remotes/origin/train/')" ] \
            || refuse "NOTCHCAST_TRAIN_ONTO ${base:0:8} is the tip of no train branch of origin"
        where='train tip'
    fi
    echo "open PRs: $(gh pr list -R "$FORK_REPO" --state open -L 200 --json number -q length || echo '?')/25"
    built=()
    for train in "${queue[@]}"; do
        build_train "$base" $train
        [ -z "$stacked" ] || preflight
        tell_drops
        [ "$stacked" = "$train" ] || status=1
        [ -n "$stacked" ] || continue
        branch=$(train_branch $stacked)
        leftover=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
        [ -z "$leftover" ] || [ -n "$auto" ] \
            || refuse "origin already has $branch; land it or delete it: git push origin --delete $branch"
        if [ -n "$leftover" ]; then
            # The lease makes one queue, so it is an earlier tick's: one kept by NOT LANDED would jam every tick.
            echo "train: $branch is left from an earlier run; scrapping it"
            scrap_train "$branch" "$leftover"
        fi
        built+=("$branch $tip $runner $stacked")
    done
    queue=()
    [ ${#built[@]} -gt 0 ] || break
    for entry in "${built[@]}"; do
        read -r branch sha runner train <<< "$entry"
        start_train "$base"
    done
    landed=
    for entry in "${built[@]}"; do
        read -r branch sha runner train <<< "$entry"
        if wait_train "$branch" "$sha"; then
            if [ -n "$landed" ]; then
                echo "STALE $branch: green on main ${base:0:8}, which #$landed has moved; running it again"
                scrap_train "$branch" "$sha"
                queue+=("$train")
                continue
            fi
            settle "$branch"
            echo "GREEN $branch ${sha:0:8} on $where ${base:0:8}: notchcast/land.sh --train-run $sha $train"
            [ -n "$auto" ] || continue
            set +e
            land_batch "$sha" $train 2>&1 | tee "$scratch/landing"
            landing=${PIPESTATUS[0]}
            set -e
            if [ "$landing" -eq 0 ]; then
                held=$(sed -n 's/^landing is held for #\([0-9]*\): the train is cut to it$/\1/p' "$scratch/landing")
                landed=${held:-$train}
                echo "LANDED #$landed"
                rest=$(tr ' ' '\n' <<< "$train" | grep -vxF "$landed" | paste -sd' ' - || true)
                [ -z "$held" ] || echo "HELD #${rest// / #}: landing is held for #$held, so land.sh landed only it; the queue takes the rest again"
            elif [ "$landing" -eq 3 ]; then
                status=1
                refused_for_good "$train" "$branch" "$runner"
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
