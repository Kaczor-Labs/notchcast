#!/bin/bash
# Sourced by land.sh, train.sh and local-ci.sh: the one merge of a PR onto main, and the cheap checks on the merged tree.
# The caller sets top (its repository), head, pr_title and pr_body, and defines tree_at <commit>, which leaves the
# shell in a clean tree at that commit.
merge_tools=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$merge_tools/drift-gates.sh"
# Those of the names $1 (space separated) listed one per line in file $2, space separated.
listed_in() { grep -xF -f <(tr ' ' '\n' <<< "$1" | grep .) "$2" | sort -u | paste -sd' ' - || true; }
# The harnesses of the tree here in both HOSTED_ONLY_TESTS and CI_SKIP_TESTS: no run proves one, so land.sh
# refuses a PR that selects one.
unprovable_list() {
    (source notchcast/config.env
    comm -12 <(tr ' ' '\n' <<< "$HOSTED_ONLY_TESTS" | sort -u) <(tr ' ' '\n' <<< "$CI_SKIP_TESTS" | sort -u) | paste -sd' ' -)
}
# Check runs on the commit, not the PR's statusCheckRollup: the rollup omits dispatched runs, and a PR
# GitHub calls conflicting gets no pull_request run at all. Cancelled or skipped runs count only alone, the
# newest run's (by check suite: a job cancelled before it started takes the cancel time as its start).
# A cancelled one is pending while its re-run or a newer run of its workflow on the head still runs.
check_run() {
    local verdict suite
    verdict=$(gh api "repos/$FORK_REPO/commits/$1/check-runs?check_name=$2&filter=all" \
        --jq '[.check_runs[] | select(.app.slug == "github-actions")] | (map(select(.conclusion != "cancelled" and .conclusion != "skipped")) | max_by([.started_at, .id])) // max_by([.check_suite.id, .started_at, .id]) | if . == null then "none" elif .status != "completed" then "pending" elif .conclusion == "cancelled" then "cancelled \(.check_suite.id)" else .conclusion end') || return
    suite=${verdict#cancelled }
    [ "$suite" != "$verdict" ] || { printf '%s\n' "$verdict"; return; }
    if [[ "$suite" =~ ^[0-9]+$ ]] && verdict=$(gh api "repos/$FORK_REPO/actions/runs?head_sha=$1&per_page=100" \
        --jq ".workflow_runs | (map(select(.check_suite_id == $suite)) | first) as \$c | if \$c and any(.[]; .workflow_id == \$c.workflow_id and .check_suite_id >= $suite and .status != \"completed\") then \"pending\" else \"cancelled\" end"); then
        printf '%s\n' "$verdict"
    else echo cancelled; fi
}
check_defect_tests() {
    local onto=$1 candidate=$2 title=$3 body=$4 changed
    title=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')
    title=${title#notchcast: }
    [[ "$title" == 'fix '* ]] || return 0
    if grep -Eq '^No test: [^[:space:]].*' <<< "$body"; then return 0; fi
    changed=$(git diff --name-only --diff-filter=AMR "$onto" "$candidate") || refuse 'cannot read defect test diff'
    grep -Eq '^Tests/[^/]+-test\.swift$|^notchcast/(.*/)?[^/]+-test\.[^/]+$' <<< "$changed" \
        || refuse 'defect fix needs a changed test or No test: <reason>'
}
# The squash commit message of PR $pr, from pr_title, pr_body and the drift_signoff merge_onto set.
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
# Refuses the commit message in file $1 when it names something private.
check_message() { "$merge_tools/check-identity.sh" message "$1" || refuse 'commit message names something private'; }
drift_fixtures_changed() {
    local changed
    changed=$(git diff --name-only "$1" HEAD -- 'notchcast/check-drift*' notchcast/bin/swiftgraph.py notchcast/config.env) \
        || refuse 'cannot read drift tooling diff'
    [ -n "$changed" ]
}
# Tests cannot prove a gate change safe, so tooling and land.sh changes carry a sign-off into history.
check_drift_tooling() {
    local onto=$1 body=$2 tools=$3 fixtures=false tooling
    drift_signoff=
    tooling=$(cat "$merge_tools/land-tooling.txt") || refuse 'cannot read notchcast/land-tooling.txt'
    if drift_fixtures_changed "$onto"; then
        fixtures=true
    elif git diff --quiet "$onto" HEAD -- $tooling; then
        return 0
    fi
    drift_signoff=$(grep -m1 -E '^Drift tooling: [^[:space:]].*' <<< "$body") \
        || refuse 'drift tooling or land.sh changed: the PR body needs a line Drift tooling: <reason>'
    [ "$fixtures" = true ] || return 0
    [ -f notchcast/check-drift-test.py ] || refuse 'the PR deletes notchcast/check-drift-test.py; the drift fixtures must stay'
    cp "$tools/check-drift-test.py" notchcast/check-drift-test.py
    python3 -I notchcast/check-drift-test.py || refuse 'drift fixtures'
    git checkout -q HEAD -- notchcast/check-drift-test.py
}
# Sync's rebase rewrites main, so a PR cut before it shares only upstream with the new main, and a plain merge sees
# every one of our commits twice. sync.yml records each replaced main tip under refs/notchcast/synced/; the PR's
# fork point is its merge base with the newest such tip whose shared history main no longer has. A PR that merged
# the new main since ("Update branch") has a plain merge base outside that tip and keeps the plain merge.
# Merges $head onto $1 in a clean tree and runs the cheap checks; any real conflict is refused.
merge_onto() {
    local onto=$1 file revived unmerged words
    cd "$top"
    # merge=notchcast-words files merge by word, with the driver beside this file, never the PR's copy of it.
    words="merge.notchcast-words.driver=python3 '$merge_tools/merge-words.py' %O %A %B"
    fork=$(bash "$merge_tools/fork-point.sh" "$onto" "$head")
    tree_at "$onto"
    if [ "$fork" = "$(git merge-base "$onto" "$head")" ]; then
        git -c "$words" -c core.hooksPath=/dev/null merge --no-commit --no-ff "$head" >/dev/null 2>&1 || true
    else
        echo "merging from ${fork:0:8}, the PR's fork point on main before a Sync rewrite"
        git -c "$words" merge-recursive "$fork" -- HEAD "$head" >/dev/null 2>&1 || true
        git rev-parse "$head" > "$(git rev-parse --git-path MERGE_HEAD)"
    fi
    # Generated files (ci.py GENERATED) keep main's version, conflicting or not, and main's Generated workflow
    # rewrites them, so the PR's copies never land and the green head still proves the code. Any other conflict is refused.
    generated=($(python3 -c 'from notchcast.ci import GENERATED; print(" ".join(GENERATED))'))
    # Only the ones main has: a newly generated file is not on main until its first landing.
    generated=($(git ls-tree -r --name-only "$onto" -- "${generated[@]}"))
    [ ${#generated[@]} -eq 0 ] || git checkout "$onto" -- "${generated[@]}"
    # The string catalog conflicts on neighbouring keys; xcstrings-union.py merges it by key or exits non-zero.
    if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Localizable.xcstrings; then
        python3 notchcast/xcstrings-union.py --git --main-ref "$onto" || refuse 'string catalog conflict xcstrings-union.py cannot merge'
    fi
    if git diff --name-only --diff-filter=U | grep -qxF Tinycast/Resources/Notchcast.xcstrings; then
        python3 notchcast/xcstrings-union.py --git --main-ref "$onto" --catalog Tinycast/Resources/Notchcast.xcstrings || refuse 'fork string catalog conflict'
    fi
    unmerged=$(git diff --name-only --diff-filter=U)
    [ -z "$unmerged" ] || refuse "merge conflict: $(echo $unmerged)"
    git -c core.hooksPath=/dev/null -c user.name="$MAINTAINER_NAME" -c user.email="$MAINTAINER_EMAIL" \
        commit --quiet --allow-empty --no-edit -m "Merge $head"
    # A union merge keeps a line the PR deleted when main appended next to it; refuse instead of reviving it.
    for file in $(awk '$2 == "merge=union" {print $1}' .gitattributes 2>/dev/null); do
        revived=$(comm -12 <(comm -23 <(git show "$fork:$file" 2>/dev/null | sort -u) <(git show "$head:$file" 2>/dev/null | sort -u)) \
            <(sort -u "$file" 2>/dev/null))
        [ -z "$revived" ] || refuse "union merge revives lines the PR removed from $file: $revived"
    done
    [ "$(git rev-parse 'HEAD^{tree}')" != "$(git rev-parse "$onto^{tree}")" ] || refuse 'nothing to land: main already has this change'
    run_drift_gates "$onto"
    check_drift_tooling "$onto" "$pr_body" "$drift_tools"
    check_defect_tests "$fork" "$head" "$pr_title" "$pr_body"
    notchcast/check-bundle-readme.sh || refuse 'two README.md files under Tinycast/ break the Xcode build'
}
