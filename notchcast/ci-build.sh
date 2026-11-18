#!/bin/bash
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")/.." && pwd)
source "$TOOLS/notchcast/config.env"
step() {
    echo "$1" > "$RUNNER_TEMP/step"
    echo "::group::$1"
}
step xcode
source "$TOOLS/notchcast/ci-xcode.sh"
# The fork-strings check compares against upstream's catalog, so fetch upstream first.
step upstream
bash "$TOOLS/notchcast/fetch-upstream.sh" --no-tags
export UPSTREAM=$(git merge-base HEAD refs/remotes/upstream/main)
step xcstrings
if [ -n "${BASE_SHA:-}" ]; then
    python3 notchcast/test-xcstrings.py
    python3 notchcast/check-xcstrings-order.py --base-ref "$BASE_SHA" --head "$HEAD_SHA"
fi
step xcodegen
source "$TOOLS/notchcast/ci-xcodegen.sh"
"$XCODEGEN" generate --quiet
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
# pr.yml runs the script tests and the harnesses in their own jobs; local-ci.sh runs them here.
if [ -z "${NOTCHCAST_HARNESSES_SHARDED:-}" ]; then
    step script-tests
    python3 notchcast/script-tests.py
fi
step build
# lsregister hangs on runners and Xcode only notes a failed registration, so kill it on our products.
(
    while kill -0 "$$"; do
        pgrep -f lsregister | while read -r pid; do
            case "$(ps -o args= -p "$pid")" in *"lsregister "*" $RUNNER_TEMP/"*) kill -KILL "$pid" || true ;; esac
        done || true
        sleep 1
    done
) >/dev/null 2>&1 &
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
    -jobs "${CHAD_BUILD_QUEUE_JOBS:-4}" -derivedDataPath "$RUNNER_TEMP/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build -quiet
step identity
bash "$TOOLS/notchcast/check-identity.sh" app "$RUNNER_TEMP/DerivedData/Build/Products/Debug/$APP_NAME Dev.app"
step name-override
python3 notchcast/name-override.py --verify "$RUNNER_TEMP/DerivedData/Build/Products/Debug/$APP_NAME Dev.app"
step lint
source "$TOOLS/notchcast/ci-swiftlint.sh"
./Scripts/lint.sh
if [ -z "${NOTCHCAST_HARNESSES_SHARDED:-}" ]; then
    step harnesses
    bash "$TOOLS/notchcast/ci-tests.sh"
fi
step complete
