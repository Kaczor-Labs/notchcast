#!/bin/bash
# The checks of ci-build.sh that need no Mac: pr.yml runs them in its Linux job, ci-build.sh otherwise.
# Run from the checkout under test; BASE_SHA and HEAD_SHA name a PR's range.
set -euo pipefail
step() {
    echo "$1" > "$RUNNER_TEMP/step"
    echo "::group::$1"
}
# The fork-strings check compares against upstream's catalog, so fetch upstream first.
step upstream
bash "$(dirname "${BASH_SOURCE[0]}")/fetch-upstream.sh" --no-tags
export UPSTREAM=$(git merge-base HEAD refs/remotes/upstream/main)
step xcstrings
if [ -n "${BASE_SHA:-}" ]; then
    python3 notchcast/test-xcstrings.py
    python3 notchcast/check-xcstrings-order.py --base-ref "$BASE_SHA" --head "$HEAD_SHA"
fi
step bundle-readme
bash notchcast/check-bundle-readme.sh
if [ -n "${BASE_SHA:-}" ]; then
    step module-harness
    python3 notchcast/check-module-harness.py "$BASE_SHA" "$HEAD_SHA"
fi
step config
python3 notchcast/check-config.py
if [ -n "${BASE_SHA:-}" ]; then
    python3 notchcast/check-addons.py --branch "${NOTCHCAST_READY_BRANCH:-${GITHUB_HEAD_REF:-}}" \
        --base "$BASE_SHA" --head "$HEAD_SHA" --upstream "$UPSTREAM"
fi
