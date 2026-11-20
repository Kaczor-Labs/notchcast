#!/bin/bash
# script-tests: macos (update.sh's PlistBuddy and ditto)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/update.sh" "$HERE/config.env" "$WORK/"
printf '#!/bin/bash\n[ "${INSTALL_STATUS:-0}" = 0 ] || exit "$INSTALL_STATUS"\ntouch "$HOME/installed"\n' > "$WORK/install-app.sh"
chmod +x "$WORK/install-app.sh"
mkdir -p "$WORK/Fixture.app/Contents"
printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.notchcast</string><key>CFBundleShortVersionString</key><string>0.12.8.snapshot.20261107210745</string></dict></plist>' > "$WORK/Fixture.app/Contents/Info.plist"
export FIXTURE="$WORK/Fixture.app"
MIXED_TAGS=$'v0.12.8.snapshot.20261107210745\nv0.12.10-beta.135\nv0.12.8.snapshot.20261107201744\nv0.12.8'
LATEST=v0.12.8.snapshot.20261107210745
export RELEASE_TAGS="$MIXED_TAGS"
gh() {
    case "$1 $2" in
        'release list')
            local limit=30
            while [ "$1" != --jq ]; do
                case "$1" in
                    -L) limit=$2; shift 2 ;;
                    *) shift ;;
                esac
            done
            printf '%s\n' "$RELEASE_TAGS" | jq -Rn --argjson limit "$limit" '[inputs | {tagName: ., isDraft: false}] | .[:$limit]' | jq -r "$2"
            ;;
        'release download') printf '%s\n' "$3" > "$HOME/downloaded" ;;
        # RUNS: one green "<id> <branch> <title>" per line, newest first; each artifact holds Notchcast-<PR_VERSION>.zip.
        'run list')
            local branch=''
            while [ "$1" != --jq ]; do
                case "$1" in
                    -b) branch=$2; shift 2 ;;
                    *) shift ;;
                esac
            done
            printf '%s\n' "$RUNS" | jq -Rn --arg branch "$branch" '[inputs | select(. != "")
                | capture("^(?<databaseId>[0-9]+) (?<headBranch>[^ ]+) (?<displayTitle>.*)$")
                | select($branch == "" or .headBranch == $branch)]' | jq -r "$2"
            ;;
        'run download')
            [ -n "$PR_VERSION" ] || return 1
            printf '%s\n' "$3" > "$HOME/downloaded"
            touch "${*: -1}/Notchcast-$PR_VERSION.zip"
            ;;
        'pr view') jq -nr --arg head "$PR_HEAD" '{headRefOid: $head}' | jq -r "${*: -1}" ;;
    esac
}
# Signed by SIGNER: only the one-call check with the requirement that names its leaf passes.
SIGNER=95280FD4EC25303CCC1FE2AA2A5E8B0A1A757DCC
codesign() { [ "$*" = "--verify --deep --strict -R=certificate leaf = H\"$SIGNER\" ${*: -1}" ]; }
ditto() { cp -R "$FIXTURE" "$4/New.app"; }
xattr() { return 0; }
ioreg() { touch "$HOME/idle-read"; echo '"HIDIdleTime" = 0'; }
sleep() { touch "$HOME/slept"; }
export SIGNER RUNS='' PR_VERSION='' PR_HEAD=''
export -f gh codesign ditto xattr ioreg sleep
run_case() {
    local name=$1 installed=$2 expected=$3
    shift 3
    export HOME="$WORK/$name" NOTCHCAST_APP="$WORK/$name/App.app"
    mkdir -p "$HOME/.config/notchcast"
    [ "${PIN:-}" = none ] || echo "SIGN_SHA1=${PIN:-95280FD4EC25303CCC1FE2AA2A5E8B0A1A757DCC}" > "$HOME/.config/notchcast/private.env"
    if [ "$installed" != no ]; then
        cp -R "$FIXTURE" "$NOTCHCAST_APP"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $installed" "$NOTCHCAST_APP/Contents/Info.plist"
    fi
    if [ "$expected" != none ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${expected#v}" "$FIXTURE/Contents/Info.plist"
    fi
    bash "$WORK/update.sh" "$@" > "$HOME/log" 2>&1 || { cat "$HOME/log"; return 1; }
    if [ "$expected" = none ]; then
        test ! -f "$HOME/downloaded" || { echo "FAIL: $name downloaded a release"; return 1; }
        test ! -f "$HOME/installed" || { echo "FAIL: $name installed a release"; return 1; }
    else
        test -f "$HOME/downloaded" || { echo "FAIL: $name did not download"; return 1; }
        grep -qxF "$expected" "$HOME/downloaded" || { echo "FAIL: $name downloaded the wrong tag"; cat "$HOME/downloaded"; return 1; }
        test -f "$HOME/installed" || { echo "FAIL: $name did not install"; cat "$HOME/log"; return 1; }
    fi
    test ! -f "$HOME/idle-read" || { echo "FAIL: $name read idle time"; return 1; }
    test ! -f "$HOME/slept" || { echo "FAIL: $name waited"; return 1; }
    ! grep -qiE 'idle|in use|next run' "$HOME/log" || { echo "FAIL: $name deferred"; cat "$HOME/log"; return 1; }
    echo "PASS: $name"
}
run_case install-over-busy-mac 0.12.7 "$LATEST" --install
run_case automatic-over-busy-mac 0.12.7 "$LATEST"
run_case first-install no "$LATEST" --install
run_case older-snapshot 0.12.8.snapshot.20261107201744 "$LATEST"
run_case installed-beta 0.12.10-beta.135 "$LATEST"
run_case same-snapshot "${LATEST#v}" none
run_case installed-newer-snapshot 0.12.8.snapshot.20261108000000 none
export RELEASE_TAGS=$'manual.snapshot.20261108000000\n0.12.8.snapshot.20261108000000\nv0.12.8.snapshot.20261107210745'
run_case malformed-snapshot-tags 0.12.8.snapshot.20261107201744 "$LATEST"
export RELEASE_TAGS=$'v0.12.10-beta.135\nv0.12.8'
run_case mirrors-only 0.12.8.snapshot.20261107201744 none
export RELEASE_TAGS="$MIXED_TAGS"$'\nv0.12.7-beta.1.snapshot.20261108000000'
run_case lower-base-newer-snapshot "${LATEST#v}" v0.12.7-beta.1.snapshot.20261108000000
printf -v RELEASE_TAGS 'v0.12.10-beta.%s\n' {1..30}
RELEASE_TAGS+="$LATEST"
run_case snapshot-after-30-mirrors 0.12.8.snapshot.20261107201744 "$LATEST"
export RELEASE_TAGS="$LATEST"
refused_case() {
    local name=$1 message=$2
    STATUS=0
    run_case "$name" 0.12.7 "$LATEST" > /dev/null 2>&1 || STATUS=$?
    test "$STATUS" != 0 || { echo "FAIL: $name installed"; exit 1; }
    test ! -f "$HOME/installed" || { echo "FAIL: $name installed"; exit 1; }
    grep -q "$message" "$HOME/log" || { echo "FAIL: $name did not say why"; cat "$HOME/log"; exit 1; }
    echo "PASS: $name"
}
PIN=0000000000000000000000000000000000000000 refused_case pin-differs 'not signed by'
SIGNER=1111111111111111111111111111111111111111 refused_case other-signer 'not signed by'
# The pin comes only from private.env: one in the tooling's config.env, as a pushed main could add, is ignored.
echo 'SIGN_SHA1=95280FD4EC25303CCC1FE2AA2A5E8B0A1A757DCC' >> "$WORK/config.env"
PIN=none refused_case no-private-env 'no SIGN_SHA1'
PIN=lowercase-or-missing refused_case no-private-pin 'no SIGN_SHA1'
test ! -f "$HOME/downloaded" || { echo 'FAIL: no-private-pin downloaded a release'; exit 1; }
echo 'PASS: update.sh refuses without a SIGN_SHA1 in private.env, whatever config.env says'

# Test builds: --pr=<n> installs the PR's newest green Test build only from its current head, then holds it.
HEAD_SHA=0123abcd89ef0123456789abcdef0123456789ab
TEST_VERSION=0.12.8.pr7.0123abcd
export RELEASE_TAGS="$LATEST" RUNS=$'42 pr-branch Test build #7\n41 main Test build #70\n40 main Test build #7\n39 main Test build #7' PR_HEAD="$HEAD_SHA"
pr_case() {
    local name=$1 status=$2 message=$3 installs=$4
    shift 4
    export HOME="$WORK/$name"
    mkdir -p "$HOME"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PR_VERSION" "$FIXTURE/Contents/Info.plist" 2>/dev/null || true
    local got=0
    bash "$WORK/update.sh" "$@" > "$HOME/log" 2>&1 || got=$?
    test "$got" = "$status" || { echo "FAIL: $name exited $got, wanted $status"; cat "$HOME/log"; exit 1; }
    grep -q -- "$message" "$HOME/log" || { echo "FAIL: $name did not say '$message'"; cat "$HOME/log"; exit 1; }
    if [ "$installs" = yes ]; then
        test -f "$HOME/installed" || { echo "FAIL: $name did not install"; cat "$HOME/log"; exit 1; }
    else
        test ! -f "$HOME/installed" || { echo "FAIL: $name installed"; cat "$HOME/log"; exit 1; }
    fi
    echo "PASS: $name"
}
for args in --pr= --pr=0 --pr=7x "--pr=7 --restore" "--restore --pr=7"; do
    # shellcheck disable=SC2086
    PR_VERSION="$TEST_VERSION" pr_case "usage-${args// /_}" 2 Usage no $args
done
# Each case runs in a fresh copy of BENCH: a home with the newest snapshot installed and the pin.
BENCH="$WORK/bench"
mkdir -p "$BENCH/.config/notchcast"
echo "SIGN_SHA1=$SIGNER" > "$BENCH/.config/notchcast/private.env"
cp -R "$FIXTURE" "$BENCH/App.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${LATEST#v}" "$BENCH/App.app/Contents/Info.plist"
bench() {
    local name=$1
    shift
    cp -R "$BENCH" "$WORK/$name"
    export NOTCHCAST_APP="$WORK/$name/App.app"
    pr_case "$name" "$@"
}
PR_VERSION="$TEST_VERSION" bench pr-dry-run 0 "would install test build $TEST_VERSION" no --pr=7 --dry-run
grep -qxF 40 "$WORK/pr-dry-run/downloaded" || { echo 'FAIL: --pr took another run than the newest green #7 from main'; exit 1; }
PR_VERSION="$TEST_VERSION" PR_HEAD=fedcba9876543210fedcba9876543210fedcba98 bench pr-head-moved 1 "not PR #7's current head fedcba98" no --pr=7
PR_VERSION="$TEST_VERSION" SIGNER=1111111111111111111111111111111111111111 bench pr-other-signer 1 'not signed by' no --pr=7
PR_VERSION="$TEST_VERSION" SIGNER=1111111111111111111111111111111111111111 bench pr-dry-run-other-signer 1 'not signed by' no --pr=7 --dry-run
PR_VERSION="$TEST_VERSION" RUNS='40 main Test build #70' bench pr-no-run 1 'gh workflow run test-build.yml .* -f pr=7' no --pr=7
PR_VERSION='' bench pr-no-artifact 1 'no test-build artifact' no --pr=7
PR_VERSION="$TEST_VERSION" bench pr-install 0 "holding test build $TEST_VERSION" yes --pr=7
test "$(cat "$WORK/pr-install/Library/Application Support/notchcast/test-build")" = "$TEST_VERSION" \
    || { echo 'FAIL: pr-install did not record the held version'; exit 1; }
# What install-app.sh would have left in place: the test build, held.
BENCH="$WORK/pr-install"
rm -f "$BENCH/installed" "$BENCH/downloaded"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TEST_VERSION" "$BENCH/App.app/Contents/Info.plist"
PR_VERSION="$TEST_VERSION" bench held 0 "test build $TEST_VERSION is held" no
PR_VERSION="$TEST_VERSION" bench held-install 0 "test build $TEST_VERSION is held" no --install
PR_VERSION="${LATEST#v}" bench restore-dry-run 0 "preparing $LATEST" no --restore --dry-run
test -f "$WORK/restore-dry-run/Library/Application Support/notchcast/test-build" || { echo 'FAIL: a dry --restore dropped the hold'; exit 1; }
PR_VERSION="${LATEST#v}" bench restore 0 "preparing $LATEST" yes --restore
grep -qxF "$LATEST" "$WORK/restore/downloaded" || { echo 'FAIL: --restore did not take the newest snapshot'; exit 1; }
test ! -f "$WORK/restore/Library/Application Support/notchcast/test-build" || { echo 'FAIL: --restore kept the hold'; exit 1; }
# --restore that cannot install the newest snapshot fails, naming --restore --retry when the snapshot was refused.
REFUSED="$BENCH/Library/Application Support/notchcast/refused-release"
echo "${LATEST#v}" > "$REFUSED"
PR_VERSION="${LATEST#v}" bench restore-refused 1 'run update.sh --restore --retry' no --restore
grep -q "$TEST_VERSION is still installed" "$WORK/restore-refused/log" || { echo 'FAIL: restore-refused did not say what stays'; exit 1; }
PR_VERSION="${LATEST#v}" bench restore-retry 0 "preparing $LATEST" yes --restore --retry
rm "$REFUSED"
PR_VERSION="${LATEST#v}" INSTALL_STATUS=75 bench restore-busy 1 "$TEST_VERSION is still installed" no --restore
PR_VERSION="${LATEST#v}" RELEASE_TAGS='v0.12.8' bench restore-no-snapshot 1 "$TEST_VERSION is still installed" no --restore
# A hold for a version no longer installed holds nothing.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.12.8.pr7.99999999" "$BENCH/App.app/Contents/Info.plist"
PR_VERSION="${LATEST#v}" bench stale-hold 0 "preparing $LATEST" yes
# A plain run that cannot install exits 0: refused names --retry alone, busy changes nothing.
echo "${LATEST#v}" > "$REFUSED"
PR_VERSION="${LATEST#v}" bench plain-refused 0 'run update.sh --retry to' no
rm "$REFUSED"
PR_VERSION="${LATEST#v}" INSTALL_STATUS=75 bench plain-busy 0 'another install is running' no
echo 'PASS: update.sh --pr installs only a green test build of the current head, signed by us, and --restore ends its hold'
