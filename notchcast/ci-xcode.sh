#!/bin/bash
set -euo pipefail
if [ -n "${NOTCHCAST_XCODE_FROM_RUNNER:-}" ]; then
    # A sandboxed runner cannot run xcodebuild and names its Xcode itself (README, Runners): the version file answers.
    XCODE_PATH=${DEVELOPER_DIR:-}
    XCODE_PATH=${XCODE_PATH%/Contents/Developer}
    version="Xcode $(python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleShortVersionString"])' \
        "$XCODE_PATH/Contents/version.plist")" || version=
else
    XCODE_PATH="$(find -E /Applications -maxdepth 1 -type d -regex '.*/Xcode_27(\.[0-9]+)*\.app' | sort -V | tail -n1)"
    if [ -z "$XCODE_PATH" ]; then XCODE_PATH=/Applications/Xcode.app; fi
    export DEVELOPER_DIR="$XCODE_PATH/Contents/Developer"
    version=$(xcodebuild -version)  # no pipe into head: with pipefail, SIGPIPE on xcodebuild failed this at random
fi
[[ ${version%%$'\n'*} =~ ^Xcode\ 27(\.[0-9]+)*$ ]] || {
    echo "::error::No released Xcode 27.x on this runner"; exit 1;
}
echo "Using $XCODE_PATH"
if [ -n "${GITHUB_ENV:-}" ]; then echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"; fi
