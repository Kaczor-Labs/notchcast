#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/notchcast" "$scratch/Scripts" "$scratch/tmp"
cp "$root/notchcast/ci-tests.sh" "$root/notchcast/config.env" "$scratch/notchcast/"
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
    CI_SKIP_TESTS=inherited bash notchcast/ci-tests.sh
    if [ "$runner" = github-hosted ]; then
        grep -qw ClipboardTextTests "$SKIPS"
    else
        [ ! -s "$SKIPS" ] || { echo "FAIL: $runner skipped harnesses"; exit 1; }
    fi
done
echo 'PASS: CI wrapper preserves skips only on GitHub-hosted runners'
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
