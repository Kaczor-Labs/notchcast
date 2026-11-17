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

# A red harness fails CI without a second run of our tree; only the upstream tree runs again.
cat > "$scratch/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
echo "$PWD" >> "$CALLS"
case $PWD in */pristine) exit 0 ;; esac
mkdir -p "$TMPDIR/tinycast-harness"
echo "FAIL X" > "$TMPDIR/tinycast-harness/X.log"
touch "$TMPDIR/tinycast-harness/X.failed"
exit 1
STUB
mkdir -p "$scratch/Tests" "$scratch/runner"
touch "$scratch/Tests/X.swift"
git init --quiet
git add -A
git -c user.name=Fixture -c user.email=fixture@example.com commit --quiet -m base
export CALLS="$scratch/calls" RUNNER_TEMP="$scratch/runner" UPSTREAM=HEAD
unset RUNNER_ENVIRONMENT
set +e
out=$(bash notchcast/ci-tests.sh 2>&1)
status=$?
set -e
[ "$status" -eq 1 ] || { echo "FAIL: a red harness exited $status"; exit 1; }
ours=$(grep -cv '/pristine$' "$CALLS")
[ "$ours" -eq 1 ] || { echo "FAIL: our tree ran $ours times"; exit 1; }
grep -q '::error::X fails with our commits and passes on upstream' <<<"$out" \
    || { echo "FAIL: no upstream verdict in: $out"; exit 1; }
echo 'PASS: a red harness fails CI and is never rerun on our tree'
