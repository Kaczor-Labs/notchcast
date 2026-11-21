#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/notchcast" "$scratch/Scripts" "$scratch/tmp" "$scratch/bin"
cp "$root/notchcast/"{ci-tests.sh,config.env,harness-tags.sh,harness_inputs.py,command-harness-sources.sh} "$scratch/notchcast/"
printf '#!/bin/bash\necho Linux\n' > "$scratch/bin/uname"
chmod +x "$scratch/bin/uname"
export PATH="$scratch/bin:$PATH"
cat > "$scratch/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
printf '%s' "${CI_SKIP_TESTS:-}" > "$SKIPS"
STUB
chmod +x "$scratch/Scripts/run-tests.sh"
cd "$scratch"
export TMPDIR="$scratch/tmp" SKIPS="$scratch/skips" GITHUB_ACTIONS=true
for runner in local self-hosted github-hosted; do
    export RUNNER_ENVIRONMENT=$runner
    [ "$runner" != local ] || unset RUNNER_ENVIRONMENT
    CI_SKIP_TESTS=inherited bash notchcast/ci-tests.sh > "$scratch/out"
    if [ "$runner" = github-hosted ]; then
        grep -qw ClipboardTextTests "$SKIPS"
    else
        [ ! -s "$SKIPS" ] || { echo "FAIL: $runner skipped harnesses"; exit 1; }
    fi
done
echo 'PASS: CI wrapper keeps the hosted VM skips on GitHub-hosted runners only'
# A harness naming one of these APIs could touch a working Mac, so it must be listed as hosted-only (hosted-only-test.sh).
source "$root/notchcast/config.env"
risky='NSWindow\(|NSPanel\(|PalettePanel\(|orderFront|becomeKey|makeKey|NSApplication\.shared|NSApp\.|/usr/bin/open|NSWorkspace|NSRunningApplication|AudioObjectSetPropertyData|CGEvent\(|CGEvent\.tapCreate|\.post\(tap|NSAppleScript|osascript|CFPreferencesSetValue|NSSound|NSPasteboard|AXUIElement|AVCaptureDevice|AVAudioEngine|SCStream|SecItem|KeychainSecretStore\(|NSOpenPanel|NSSavePanel|NSAlert|UNUserNotification'
unlisted=$(cd "$root/Tests" && grep -lE "$risky" *.swift | sed 's/\.swift$//' \
    | grep -vxF -e NotchcastTapFixtures -e 'ExtensionTests+MenuBar' \
    | grep -vxF -f <(tr ' ' '\n' <<< "$HOSTED_ONLY_TESTS $HIDDEN_TESTS") || true)
[ -z "$unlisted" ] || { echo "FAIL: not hosted-only (a // notchcast-hosted-only line, or HOSTED_ONLY_TESTS in notchcast/config.env): $unlisted"; exit 1; }
echo 'PASS: every harness that names a window, focus, launch, pasteboard, sound, event or preference API is hosted-only'
cat > Scripts/run-tests.sh <<'STUB'
#!/bin/bash
run() { :; }
run FixtureTests Sources/*.swift
bin="$TMPDIR/tinycast-harness"
mkdir -p "$bin"
if [ $# -eq 0 ]; then
    : > "$bin/FixtureTests.failed"
    echo 'fixture assertion failed' > "$bin/FixtureTests.log"
    exit 1
fi
if [ "$(pwd -P)" = "$FIXTURE_ROOT" ]; then
    : > "$FIXTURE_ROOT/reran"
    exit 0
fi
case "$PRISTINE_RESULT" in
    cancelled) kill -TERM "$WRAPPER_PID"; exit 1;;
    launch-error) exit 127;;
    passed) exit 0;;
    setup-error) exit 1;;
esac
: > "$bin/FixtureTests.failed"
echo 'fixture assertion failed' > "$bin/FixtureTests.log"
case "$PRISTINE_RESULT" in
    build-error) printf '[1/1] \033[31mFAIL\033[0m  FixtureTests             did not compile\n'; exit 1;;
    missing-binary) ;;
    *) touch "$bin/FixtureTests"; chmod +x "$bin/FixtureTests";;
esac
verdict='assertion failed after 0.0s'
case "$PRISTINE_RESULT" in
    crashed) verdict='crashed (signal 6) after 0.0s';;
    timed-out|assertion-in-log) verdict='timed out after 300s';;
esac
printf '[1/1] \033[31mFAIL\033[0m  %-25s %s\n' FixtureTests "$verdict"
printf '\n\033[31m--- FixtureTests ---\033[0m\n'
if [ "$PRISTINE_RESULT" = assertion-in-log ]; then
    printf '  FixtureTests assertion failed after 0.0s\n' >> "$bin/FixtureTests.log"
    printf '[1/1] \033[31mFAIL\033[0m  FixtureTests             assertion failed after 0.0s\n' >> "$bin/FixtureTests.log"
fi
cat "$bin/FixtureTests.log"
exit 1
STUB
git init -q
git config user.name Test
git config user.email test@example.com
git add Scripts notchcast
git commit -q -m 'Fixture upstream without the harness'
without_harness=$(git rev-parse HEAD)
mkdir Tests Sources
printf '// fixture harness\n' > Tests/FixtureTests.swift
printf '// fixture source\n' > Sources/Source.swift
git add Tests Sources
git commit -q -m 'Fixture upstream with the harness'
upstream=$(git rev-parse HEAD)
export FIXTURE_ROOT
FIXTURE_ROOT=$(pwd -P)
unset RUNNER_ENVIRONMENT

run_case() {
    export RUNNER_TEMP="$FIXTURE_ROOT/$1" UPSTREAM="$2" PRISTINE_RESULT="$3"
    mkdir -p "$RUNNER_TEMP"
    status=0
    bash -c 'export WRAPPER_PID=$$; exec bash notchcast/ci-tests.sh' > "$RUNNER_TEMP/out" 2>&1 || status=$?
}

expect_red() {
    if [ "$status" -eq 0 ] || [ "$(cat "$RUNNER_TEMP/harness-failures")" != FixtureTests ] \
        || [ -s "$RUNNER_TEMP/harness-excused" ]; then
        cat "$RUNNER_TEMP/out"
        echo "FAIL: ${RUNNER_TEMP##*/} did not preserve the first failure"
        return 1
    fi
    echo "PASS: ${RUNNER_TEMP##*/} preserves the first failure"
}

problems=0
run_case no-rerun "$without_harness" assertion
expect_red && [ ! -e reran ] || { echo 'FAIL: a passing rerun can hide the first failure'; problems=1; }

run_case bad-ref 0000000000000000000000000000000000000000 assertion
expect_red || problems=1

for result in launch-error setup-error build-error missing-binary passed crashed timed-out assertion-in-log; do
    run_case "$result" "$upstream" "$result"
    expect_red || problems=1
done

printf '# changed runner\n' >> Scripts/run-tests.sh
run_case changed-runner "$upstream" assertion
expect_red || problems=1
git restore Scripts/run-tests.sh

sed 's/^run FixtureTests /run -O FixtureTests /' Scripts/run-tests.sh > "$scratch/optimized-runner"
cat "$scratch/optimized-runner" > Scripts/run-tests.sh
run_case changed-optimization "$upstream" assertion
expect_red || problems=1
git restore Scripts/run-tests.sh

printf '// changed harness\n' >> Tests/FixtureTests.swift
run_case changed-harness "$upstream" assertion
expect_red || problems=1
git restore Tests/FixtureTests.swift

printf '// changed source\n' >> Sources/Source.swift
run_case changed-source "$upstream" assertion
expect_red || problems=1
git restore Sources/Source.swift

printf '// extra source\n' > Sources/Added.swift
run_case added-source "$upstream" assertion
expect_red || problems=1
mv Sources/Added.swift "$scratch/bin/Added.swift"

mkdir Hook
printf '// hook source\n' > Hook/Hook.swift
printf 'set -- "$@" Hook/Hook.swift\n' > notchcast/command-harness-sources.sh
run_case hook-source "$upstream" assertion
expect_red || problems=1
git restore notchcast/command-harness-sources.sh

run_case unchanged "$upstream" assertion
if [ "$status" -ne 0 ] || [ "$(cat "$RUNNER_TEMP/harness-excused")" != FixtureTests ] \
    || [ -s "$RUNNER_TEMP/harness-failures" ]; then
    cat "$RUNNER_TEMP/out"
    echo 'FAIL: an unchanged harness with a pristine assertion failure was not excused'
    problems=1
else
    echo 'PASS: an unchanged harness with a pristine assertion failure is excused'
fi

run_case cancelled "$upstream" cancelled
if [ "$status" -ne 143 ] || [ "$(cat "$RUNNER_TEMP/harness-failures")" != FixtureTests ] \
    || git worktree list --porcelain | grep -Fxq "worktree $RUNNER_TEMP/pristine"; then
    cat "$RUNNER_TEMP/out"
    echo 'FAIL: cancellation lost the failure or left the pristine worktree registered'
    problems=1
else
    echo 'PASS: cancellation keeps the failure and removes the pristine worktree'
fi

mkdir "$FIXTURE_ROOT/stale"
git worktree add -q --detach "$FIXTURE_ROOT/stale/pristine" "$upstream"
mv "$FIXTURE_ROOT/stale/pristine" "$FIXTURE_ROOT/stale-checkout"
run_case stale "$upstream" assertion
if [ "$status" -ne 0 ] || [ "$(cat "$RUNNER_TEMP/harness-excused")" != FixtureTests ] \
    || git worktree list --porcelain | grep -Fxq "worktree $RUNNER_TEMP/pristine"; then
    cat "$RUNNER_TEMP/out"
    echo 'FAIL: a stale registration prevented the pristine comparison'
    problems=1
else
    echo 'PASS: a stale registration is pruned before the pristine comparison'
fi
exit "$problems"
