#!/bin/bash
# The real queue filter over a stub runner: no harness is compiled or run, the stub prints what would be queued.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/Scripts" "$scratch/notchcast" "$scratch/bin"
cp "$root/notchcast/test-harnesses.sh" "$scratch/notchcast/"
echo 'HOSTED_ONLY_TESTS="KeychainTests WindowTests"' > "$scratch/notchcast/config.env"
printf '#!/bin/bash\nexit 0\n' > "$scratch/bin/python3"
cat > "$scratch/Scripts/run-tests.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
QUEUE="$TMPDIR/queue"
only=${1:-} emit_db=0 ran=3
printf '1 %s -Onone\n' PlainTests KeychainTests WindowTests > "$QUEUE"
source notchcast/test-harnesses.sh
if [ -n "$only" ]; then echo "ran $only"; else awk '{ print "ran " $2 }' "$QUEUE"; fi
STUB
chmod +x "$scratch/bin/python3" "$scratch/Scripts/run-tests.sh"
export PATH="$scratch/bin:$PATH" TMPDIR="$scratch" NOTCHCAST_PLATFORM=Darwin
unset CI_SKIP_TESTS NOTCHCAST_SHARD NOTCHCAST_ONLY_TESTS RUNNER_ENVIRONMENT NOTCHCAST_ISOLATED_RUNNER
cd "$scratch"
fail() { cat out; echo "FAIL: $1"; exit 1; }
# suite <label> [VAR=value]: the whole suite under that environment, both streams in out.
suite() { local label=$1; shift; env "$@" Scripts/run-tests.sh > out 2>&1 || fail "$label: the suite failed"; }
for where in unset RUNNER_ENVIRONMENT=self-hosted NOTCHCAST_ISOLATED_RUNNER=0; do
    [ "$where" != unset ] || where=NOTHING=1
    suite "$where" "$where"
    [ "$(grep -c '^ran ' out)" = 1 ] && grep -qx 'ran PlainTests' out || fail "$where ran a hosted-only harness"
    for name in KeychainTests WindowTests; do
        grep -q "^SKIPPED $name: hosted-only: .*HOSTED_ONLY_TESTS" out || fail "$where skipped $name without a SKIPPED line and reason"
    done
    status=0
    env "$where" Scripts/run-tests.sh KeychainTests > out 2>&1 || status=$?
    [ "$status" -eq 1 ] && grep -q '^REFUSED: KeychainTests is hosted-only: ' out && ! grep -q '^ran ' out \
        || fail "$where: naming a hosted-only harness was not refused"
    env "$where" Scripts/run-tests.sh PlainTests > out 2>&1 && grep -qx 'ran PlainTests' out || fail "$where refused a plain named run"
done
echo 'PASS: off a hosted or isolated runner a hosted-only harness is skipped with its reason, and naming it is refused'
suite selection NOTCHCAST_ONLY_TESTS='PlainTests WindowTests'
[ "$(grep -c '^SKIPPED ' out)" = 1 ] && grep -q '^SKIPPED WindowTests: ' out && grep -qx 'ran PlainTests' out \
    || fail 'a selection did not skip exactly its own hosted-only harness'
echo 'PASS: a selection skips its hosted-only harnesses too'
# The isolated runner's own service sets its variable; the test sets it only for this stub runner.
for where in RUNNER_ENVIRONMENT=github-hosted NOTCHCAST_ISOLATED_RUNNER=1; do
    suite "$where" "$where"
    [ "$(grep -c '^ran ' out)" = 3 ] && ! grep -q SKIPPED out || fail "$where did not run the whole suite"
    env "$where" Scripts/run-tests.sh KeychainTests > out 2>&1 && grep -qx 'ran KeychainTests' out || fail "$where refused a named run"
done
echo 'PASS: a GitHub-hosted or isolated runner runs hosted-only harnesses, named or in the suite'
echo 'LINUX_OK_TESTS="PlainTests KeychainTests"' >> notchcast/config.env
suite linux NOTCHCAST_PLATFORM=Linux
[ "$(grep -c '^ran ' out)" = 1 ] && grep -qx 'ran PlainTests' out && grep -q '^SKIPPED KeychainTests: hosted-only: ' out \
    && grep -q '^1 mac-only harnesses skipped on Linux .*: WindowTests$' out \
    || fail 'on Linux a linux-ok hosted-only harness was not skipped as hosted-only'
echo 'PASS: on Linux a harness that is linux-ok and hosted-only is skipped as hosted-only'
# Nothing the repository runs may claim to be the isolated runner: only that runner's service environment does.
setters=$(cd "$root" && git grep -lE 'NOTCHCAST_ISOLATED_RUNNER[]}"]*=' -- . ':!notchcast/hosted-only-test.sh' ':!*.md' || true)
[ -z "$setters" ] || { echo "FAIL: NOTCHCAST_ISOLATED_RUNNER is set in: $setters"; exit 1; }
echo 'PASS: no workflow or script sets NOTCHCAST_ISOLATED_RUNNER'
