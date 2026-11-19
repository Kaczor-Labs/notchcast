#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/notchcast" "$scratch/Scripts" "$scratch/tmp"
cp "$root/notchcast/ci-tests.sh" "$root/notchcast/config.env" "$root/notchcast/harness-tags.sh" "$scratch/notchcast/"
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
[ -z "$unlisted" ] || { echo "FAIL: not in HOSTED_ONLY_TESTS (notchcast/config.env): $unlisted"; exit 1; }
echo 'PASS: every harness that names a window, focus, launch, pasteboard, sound, event or preference API is hosted-only'
# A harness failing alone too and absent on upstream is written down for the selection check.
cat > Scripts/run-tests.sh <<'STUB'
#!/bin/bash
mkdir -p "$TMPDIR/tinycast-harness"
if [ $# -eq 0 ]; then : > "$TMPDIR/tinycast-harness/nc-New-test.failed"; fi
echo 'assertion failed' > "$TMPDIR/tinycast-harness/nc-New-test.log"
exit 1
STUB
git init -q
git config user.name Test
git config user.email test@example.com
git add Scripts notchcast
git commit -q -m 'Fixture upstream'
mkdir "$scratch/runner"
unset RUNNER_ENVIRONMENT
status=0
RUNNER_TEMP="$scratch/runner" UPSTREAM=$(git rev-parse HEAD) bash notchcast/ci-tests.sh > "$scratch/out" 2>&1 \
    || status=$?
[ "$status" -ne 0 ] || { cat "$scratch/out"; echo 'FAIL: a harness failing for good passed the run'; exit 1; }
[ "$(cat "$scratch/runner/harness-failures")" = nc-New-test ] \
    || { cat "$scratch/out"; echo 'FAIL: the failing harness was not written down'; exit 1; }
echo 'PASS: a harness that fails for good is written to harness-failures in the runner temp'
# A failing upstream comparison still leaves the harness written down.
rm -rf "$scratch/runner" tmp/tinycast-harness
mkdir "$scratch/runner"
status=0
RUNNER_TEMP="$scratch/runner" UPSTREAM=0000000000000000000000000000000000000000 bash notchcast/ci-tests.sh \
    > "$scratch/out" 2>&1 || status=$?
[ "$status" -ne 0 ] || { cat "$scratch/out"; echo 'FAIL: a failing upstream comparison passed the run'; exit 1; }
[ "$(cat "$scratch/runner/harness-failures")" = nc-New-test ] \
    || { cat "$scratch/out"; echo 'FAIL: a failing upstream comparison wrote no harness down'; exit 1; }
echo 'PASS: a harness that fails for good is written down before the upstream comparison'
# Red on upstream too: ignored for the verdict, and written down as proven nowhere by this run.
mkdir Tests "$scratch/excusing"
: > Tests/nc-New-test.swift
git add Tests
git commit -q -m 'Fixture upstream with the harness'
RUNNER_TEMP="$scratch/excusing" UPSTREAM=$(git rev-parse HEAD) bash notchcast/ci-tests.sh > "$scratch/out" 2>&1 \
    || { cat "$scratch/out"; echo 'FAIL: a harness red on upstream too failed the run'; exit 1; }
[ "$(cat "$scratch/excusing/harness-excused")" = nc-New-test ] && [ ! -s "$scratch/excusing/harness-failures" ] \
    || { cat "$scratch/out"; echo 'FAIL: a harness red on upstream too was not written to harness-excused'; exit 1; }
echo 'PASS: a harness red on upstream too passes the run and is written to harness-excused'
