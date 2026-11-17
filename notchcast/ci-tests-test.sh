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

# A red harness fails CI; the upstream tree only adds a diagnosis, and a reasoned exemption is the one escape.
cat > "$scratch/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
echo "$PWD" >> "$CALLS"
mkdir -p "$TMPDIR/tinycast-harness"
case $PWD in */pristine) exit "$PRISTINE_STATUS" ;; esac
echo "FAIL $HARNESS" > "$TMPDIR/tinycast-harness/$HARNESS.log"
touch "$TMPDIR/tinycast-harness/$HARNESS.failed"
[ -z "${LEFT_RUNNING:-}" ] || touch "$TMPDIR/tinycast-harness/$LEFT_RUNNING.running"
exit 1
STUB
mkdir -p "$scratch/Tests" "$scratch/runner"
touch "$scratch/Tests/X.swift"
cp notchcast/config.env "$scratch/config.env.orig"
git init --quiet
git add -A
git -c user.name=Fixture -c user.email=fixture@example.com commit --quiet -m base
UPSTREAM=$(git rev-parse HEAD)
export CALLS="$scratch/calls" RUNNER_TEMP="$scratch/runner" UPSTREAM
unset RUNNER_ENVIRONMENT
upstream=${UPSTREAM:0:7}
# expect <case> <exit> <line>, with HARNESS, PRISTINE_STATUS, LEFT_RUNNING and EXEMPTIONS set for the run.
expect() {
    cp "$scratch/config.env.orig" notchcast/config.env
    [ -z "${EXEMPTIONS:-}" ] || printf 'UPSTREAM_RED_HARNESSES="%s"\n' "$EXEMPTIONS" >> notchcast/config.env
    rm -rf "$TMPDIR/tinycast-harness" "$CALLS"
    set +e
    out=$(bash notchcast/ci-tests.sh 2>&1)
    status=$?
    set -e
    [ "$status" -eq "$2" ] || { echo "FAIL: $1 exited $status: $out"; exit 1; }
    grep -qF -- "$3" <<<"$out" || { echo "FAIL: $1 printed no '$3' in: $out"; exit 1; }
    ours=$(grep -cv '/pristine$' "$CALLS")
    [ "$ours" -eq 1 ] || { echo "FAIL: $1 ran our tree $ours times"; exit 1; }
    echo "PASS: $1"
}
HARNESS=X PRISTINE_STATUS=0 expect 'red, passes on upstream' 1 "::error::X fails; it passes on upstream $upstream"
HARNESS=X PRISTINE_STATUS=1 expect 'red, also fails on upstream' 1 "::error::X fails; it also fails on upstream $upstream"
HARNESS=Y PRISTINE_STATUS=0 expect 'red, does not exist on upstream' 1 "::error::Y fails; it does not exist on upstream $upstream"
HARNESS=X PRISTINE_STATUS=1 EXEMPTIONS='X: upstream ships it red' expect 'an exempt red harness is green and loud' 0 \
    '::warning::EXEMPT X is red and listed in UPSTREAM_RED_HARNESSES'
HARNESS=Y PRISTINE_STATUS=1 EXEMPTIONS='X: upstream ships it red' expect 'an exemption covers only its harness' 1 \
    "::error::Y fails; it does not exist on upstream $upstream"
HARNESS=X PRISTINE_STATUS=1 EXEMPTIONS='X' expect 'an exemption without a reason is red' 1 \
    "::error::UPSTREAM_RED_HARNESSES entry without a reason: 'X'"
HARNESS=X PRISTINE_STATUS=1 EXEMPTIONS='X: upstream ships it red' LEFT_RUNNING=Z expect 'a harness left running is red' 1 \
    '::error::Z never finished'
