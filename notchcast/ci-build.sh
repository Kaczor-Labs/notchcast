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
# pr.yml runs these checks in their own Linux job; local-ci.sh runs them here.
if [ -z "${NOTCHCAST_HARNESSES_SHARDED:-}" ]; then
    source "$TOOLS/notchcast/ci-checks.sh"
fi
step xcodegen
source "$TOOLS/notchcast/ci-xcodegen.sh"
"$XCODEGEN" generate --quiet
# pr.yml runs the script tests and the harnesses in their own steps; local-ci.sh runs them here.
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
debug_build() {
    xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
        -jobs "${CHAD_BUILD_QUEUE_JOBS:-4}" -derivedDataPath "$1/DerivedData" \
        CODE_SIGNING_ALLOWED=NO build -quiet 2>&1 | tee "$1/build.log"
}
debug_build "$RUNNER_TEMP"
step build-warnings
baseline=$(mktemp -d "$RUNNER_TEMP/warning-base.XXXXXX")
: > "$baseline/build.log"
if grep -Eq '(^|[[:space:]])warning: ' "$RUNNER_TEMP/build.log"; then
    base=${BASE_SHA:-$(git merge-base origin/main HEAD)}
    echo "Building the warning baseline at $base"
    mkdir "$baseline/src"
    git archive -o "$baseline/src.tar" "$base"
    tar -xf "$baseline/src.tar" -C "$baseline/src"
    (cd "$baseline/src" && "$XCODEGEN" generate --quiet && debug_build "$baseline")
fi
python3 "$TOOLS/notchcast/build-warnings.py" "$baseline/build.log" "$RUNNER_TEMP/build.log" \
    "$baseline/src" "$PWD"
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
