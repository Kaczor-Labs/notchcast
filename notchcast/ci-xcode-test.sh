#!/bin/bash
# ci-xcode.sh on a runner that names its own Xcode: the version file answers, and xcodebuild never starts.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
printf '#!/bin/bash\n: > "%s/xcodebuild-ran"\nexit 1\n' "$scratch" > "$scratch/bin/xcodebuild"
chmod +x "$scratch/bin/xcodebuild"
export PATH="$scratch/bin:$PATH"
# xcode <name> <version>: a fixture Xcode, and its Developer folder in DEVELOPER_DIR.
xcode() {
    mkdir -p "$scratch/$1.app/Contents/Developer"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>\n' \
        "$2" > "$scratch/$1.app/Contents/version.plist"
    export DEVELOPER_DIR="$scratch/$1.app/Contents/Developer"
}
fail() { cat "$scratch/out"; echo "FAIL: $1"; exit 1; }
# from_runner: ci-xcode.sh as pr.yml's harness-only job runs it, both streams in out.
from_runner() { NOTCHCAST_XCODE_FROM_RUNNER=1 GITHUB_ENV="$scratch/exported" bash "$root/notchcast/ci-xcode.sh" > "$scratch/out" 2>&1; }
xcode Xcode 27.2
from_runner || fail "the runner's Xcode 27.2 was refused"
grep -qx "Using $scratch/Xcode.app" "$scratch/out" && grep -qx "DEVELOPER_DIR=$DEVELOPER_DIR" "$scratch/exported" \
    || fail "the runner's Xcode was not the one used"
xcode Old 26.4
! from_runner || fail 'Xcode 26.4 was accepted'
grep -q '^::error::No released Xcode 27.x on this runner$' "$scratch/out" || fail 'Xcode 26.4 was refused without the error'
unset DEVELOPER_DIR
! from_runner || fail 'a runner without DEVELOPER_DIR passed'
grep -q '^::error::No released Xcode 27.x on this runner$' "$scratch/out" || fail 'a runner without DEVELOPER_DIR failed without the error'
[ ! -e "$scratch/xcodebuild-ran" ] || fail 'xcodebuild ran'
echo 'PASS: a runner that names its Xcode is checked by the version file alone; xcodebuild never runs'
