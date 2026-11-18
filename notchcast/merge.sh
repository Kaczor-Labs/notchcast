#!/bin/bash
# Sourced by land.sh and local-ci.sh: the one merge of a PR onto main, and the cheap checks on the merged tree.
# The caller sets top (its repository), head, pr_title and pr_body, and defines tree_at <commit>, which leaves the
# shell in a clean tree at that commit.
merge_tools=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$merge_tools/drift-gates.sh"
# Check runs on the commit, not the PR's statusCheckRollup: the rollup omits dispatched runs, and a PR
# GitHub calls conflicting gets no pull_request run at all. Cancelled or skipped runs count only alone.
check_run() {
    gh api "repos/$FORK_REPO/commits/$1/check-runs?check_name=$2&filter=all" \
        --jq '[.check_runs[] | select(.app.slug == "github-actions")] | (map(select(.conclusion != "cancelled" and .conclusion != "skipped")) | max_by([.started_at, .id])) // max_by([.started_at, .id]) | if . == null then "none" elif .status != "completed" then "pending" else .conclusion end'
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
    local onto=$1 file revived unmerged
    cd "$top"
    fork=$(bash "$merge_tools/fork-point.sh" "$onto" "$head")
    tree_at "$onto"
    if [ "$fork" = "$(git merge-base "$onto" "$head")" ]; then
        git -c core.hooksPath=/dev/null merge --no-commit --no-ff "$head" >/dev/null 2>&1 || true
    else
        echo "merging from ${fork:0:8}, the PR's fork point on main before a Sync rewrite"
        git merge-recursive "$fork" -- HEAD "$head" >/dev/null 2>&1 || true
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
