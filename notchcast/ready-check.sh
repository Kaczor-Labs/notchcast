#!/bin/bash
# Runs every gate pr.yml runs, in its order (ci-build.sh, harnesses included), on HEAD against a base ref.
# Prints one PASS line, or FAIL with the first failing gate and the log. ready-check-test.py ties it to pr.yml.
set -euo pipefail
[[ $# -le 1 ]] || { echo 'usage: ready-check.sh [base-ref, default origin/v2/stack]' >&2; exit 2; }
base_ref=${1:-origin/v2/stack}
cd "$(git rev-parse --show-toplevel)"
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
unset NOTCHCAST_HARNESSES_SHARDED
queue=()
# shellcheck disable=SC2206
if [ -n "${NOTCHCAST_BUILD_QUEUE:-}" ]; then queue=($NOTCHCAST_BUILD_QUEUE hold --); fi
echo "ready-check: ${HEAD_SHA:0:12} against $base_ref (${BASE_SHA:0:12}); log: $log"
if (cd "$tree" && ${queue[@]+"${queue[@]}"} bash notchcast/ci-build.sh) > "$log" 2>&1; then
    echo "PASS ${HEAD_SHA:0:12} against $base_ref (${BASE_SHA:0:12})"
else
    step=$(cat "$scratch/step" 2>/dev/null || echo setup)
    tail -n 40 "$log"
    echo "FAIL $step; log: $log"
    exit 1
fi
