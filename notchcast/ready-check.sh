#!/bin/bash
# Runs land.sh's drift gates, the private-data checks leaks.yml runs, then every gate pr.yml runs in its order (ci-build.sh, harnesses included),
# then check-addon-delete.py --rotate when the branch changes Tinycast/Features/Notchcast/, on HEAD against a base ref.
# Prints retried and ignored harnesses then PASS, or FAIL with the first failing gate. ready-check-test.py ties it to pr.yml.
set -euo pipefail
[[ $# -le 1 ]] || { echo 'usage: ready-check.sh [base-ref, default origin/v2/stack]' >&2; exit 2; }
base_ref=${1:-origin/v2/stack}
cd "$(git rev-parse --show-toplevel)"
# The identity gate runs with the caller's PATH and no git or Python environment that HEAD's config.env sets.
clean=(/usr/bin/env -i HOME="$HOME" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1)
# shellcheck disable=SC1091
source notchcast/config.env
if [ -f "$HOME/.config/notchcast/private.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/notchcast/private.env"
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "FAIL setup: uncommitted changes; the check builds HEAD only" >&2
    exit 1
fi
BASE_SHA=$(git rev-parse --verify --quiet "$base_ref^{commit}") || {
    echo "FAIL setup: no commit $base_ref" >&2; exit 1; }
HEAD_SHA=$(git rev-parse HEAD)
export BASE_SHA HEAD_SHA
root="$HOME/Library/Caches/notchcast/ready-check"
mkdir -p "$root"
log="$root/${HEAD_SHA:0:12}.log"
# Debug builds embed absolute source paths that no flag remaps, so build outside the home (as local-ci.sh does).
scratch=$(mktemp -d "$(getconf DARWIN_USER_TEMP_DIR)notchcast-ready.XXXXXX")
tree="$scratch/tree"
trap 'cd /; rm -rf "$scratch"' EXIT
# A shared clone with the fork's tags only, as Actions' checkout sees it (lint's check-migrations reads tags).
git clone --quiet --shared --no-checkout --no-tags "$(git rev-parse --path-format=absolute --git-common-dir)" "$tree"
git -C "$tree" checkout --quiet --detach "$HEAD_SHA"
git -C "$tree" fetch --quiet --tags "https://github.com/$FORK_REPO.git"
export RUNNER_TEMP="$scratch" TMPDIR="$scratch/tmp"
mkdir "$TMPDIR"
echo "ready-check: ${HEAD_SHA:0:12} against $base_ref (${BASE_SHA:0:12}); log: $log"
# land.sh's drift gates, with the base ref standing in for origin/main: v2 never merges onto main.
common=$(git rev-parse --path-format=absolute --git-common-dir)
git -C "$tree" fetch --quiet --no-tags "https://github.com/$UPSTREAM_REPO.git" \
    +refs/heads/main:refs/remotes/upstream/main 2>/dev/null \
    || git -C "$tree" fetch --quiet "$common" +refs/remotes/upstream/main:refs/remotes/upstream/main 2>/dev/null \
    || { echo "FAIL setup: cannot fetch upstream main" >&2; exit 1; }
git -C "$tree" update-ref refs/remotes/origin/main "$BASE_SHA"
git show "$BASE_SHA:notchcast/drift-gates.sh" > "$scratch/drift-gates.sh" 2>/dev/null || {
    echo "FAIL setup: $base_ref has no notchcast/drift-gates.sh" >&2; exit 1; }
# Upstream files this tree changes (renames count as delete plus add), as files and added/deleted lines.
upstream_touch() {
    git -C "$tree" diff --no-renames --diff-filter=MD --numstat \
        "$(git -C "$tree" merge-base "$1" refs/remotes/upstream/main)" "$1" \
        | awk '{f++; a+=($1=="-"?0:$1); d+=($2=="-"?0:$2)} END {print f+0, a+0, d+0}'
}
read -r files added deleted <<< "$(upstream_touch "$HEAD_SHA")"
read -r base_files base_added base_deleted <<< "$(upstream_touch "$BASE_SHA")"
upstream_at=$(git -C "$tree" merge-base "$HEAD_SHA" refs/remotes/upstream/main)
echo "upstream touch: $files files, +$added −$deleted (base ${upstream_at:0:12})"
printf 'delta: %+d files, %+d lines\n' $((files - base_files)) $((added + deleted - base_added - base_deleted))
branch=${NOTCHCAST_READY_BRANCH:-$(git symbolic-ref --quiet --short HEAD || true)}
if [[ "$branch" == v2/addons-* && ! "$branch" =~ ^v2/addons-core(-[0-9]+)?$ ]]; then
    # An add-on lives in fork-owned paths only, so syncing upstream never conflicts with it.
    touched=$(comm -12 <(git -C "$tree" diff --name-only --no-renames "$BASE_SHA" "$HEAD_SHA" | sort) \
        <(git -C "$tree" ls-tree -r --name-only refs/remotes/upstream/main | sort))
    if [ -n "$touched" ]; then
        echo "$touched"
        echo "FAIL footprint: $branch touches $(wc -l <<< "$touched" | tr -d ' ') upstream paths"
        exit 1
    fi
fi
# shellcheck disable=SC1091,SC2034
if ! (cd "$tree" && top="$tree" && source "$scratch/drift-gates.sh" && run_drift_gates "$BASE_SHA") > "$log" 2>&1; then
    tail -n 40 "$log"
    echo "FAIL drift; log: $log"
    exit 1
fi
# leaks.yml's private-data checks over what this branch adds, by the base's scanner and HEAD's (only adds failures).
scanners=("$tree/notchcast")
if "${clean[@]}" git -C "$tree" cat-file -e "$BASE_SHA:notchcast/check-identity.py" 2>/dev/null; then
    mkdir "$scratch/identity"
    "${clean[@]}" git -C "$tree" archive -o "$scratch/identity.tar" "$BASE_SHA" notchcast
    tar -xf "$scratch/identity.tar" -C "$scratch/identity"
    scanners=("$scratch/identity/notchcast" "$tree/notchcast")
else
    echo "identity: bootstrap, scanner from HEAD"
fi
for identity in "${scanners[@]}"; do
    for mode in diff metadata; do
        if ! (cd "$tree" && "${clean[@]}" python3 -I "$identity/check-identity.py" "$mode" "$BASE_SHA") >> "$log" 2>&1; then
            grep '^check-identity:' "$log" | tail -n 40
            echo "FAIL identity: $mode names something private; log: $log"
            exit 1
        fi
    done
done
unset NOTCHCAST_HARNESSES_SHARDED
queue=()
# shellcheck disable=SC2206
if [ -n "${NOTCHCAST_BUILD_QUEUE:-}" ]; then queue=($NOTCHCAST_BUILD_QUEUE hold --); fi
if (cd "$tree" && ${queue[@]+"${queue[@]}"} bash notchcast/ci-build.sh) >> "$log" 2>&1; then
    # A harness green only on its retry, or ignored as failing upstream too, is not a clean PASS.
    retried=$(sed -n 's/^::warning::retrying \(.*\) alone$/\1/p' "$log" | sort -u | paste -sd ' ' -)
    ignored=$(sed -n 's/^::warning::\(.*\) fails on upstream .* too; not ours, ignored$/\1/p' "$log" \
        | sort -u | paste -sd ' ' -)
    echo "retried: ${retried:-none}"
    echo "ignored (fails upstream too): ${ignored:-none}"
    # The delete test costs one more Debug build, so only a branch that changes add-on code pays it.
    if [ -n "$(git -C "$tree" diff --name-only "$BASE_SHA" "$HEAD_SHA" -- Tinycast/Features/Notchcast/)" ]; then
        if ! (cd "$tree" && python3 -I notchcast/check-addon-delete.py --rotate --ref "$HEAD_SHA") >> "$log" 2>&1; then
            sed -n '/^FAIL delete/p' "$log"
            echo "FAIL addon-delete; log: $log"
            exit 1
        fi
        sed -nE 's/^(PASS delete .*|no add-on folders .*)$/addon-delete: \1/p' "$log"
    fi
    echo "PASS ${HEAD_SHA:0:12} against $base_ref (${BASE_SHA:0:12})"
else
    step=$(cat "$scratch/step" 2>/dev/null || echo setup)
    tail -n 40 "$log"
    echo "FAIL $step; log: $log"
    exit 1
fi
