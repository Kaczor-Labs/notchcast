#!/bin/bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/notchcast" "$scratch/bin"
cp "${LAND_SCRIPT:-$root/notchcast/land.sh}" "$scratch/repo/notchcast/land.sh"
cp "$root/notchcast/config.env" "$root/notchcast/local-build-status.sh" "$root/notchcast/sync-wait.sh" "$root/notchcast/hold.sh" "$root/notchcast/drift-gates.sh" "$root/notchcast/merge.sh" "$root/notchcast/land-tooling.txt" "$scratch/repo/notchcast/"
cp "$root/notchcast/app-proof.py" "$root/notchcast/ci.py" "$root/notchcast/train.sh" "$scratch/repo/notchcast/"
echo '{"fixture-proof": ["Tinycast/Fixture/Proved.swift"]}' > "$scratch/repo/notchcast/app-proofs.json"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
    *--json*state*) printf '{"state":"OPEN","isDraft":false,"headRefOid":"%s","headRefName":"fixture","baseRefName":"%s"}\n' "$HEAD_SHA" "$BASE_NAME" ;;
    *check-runs*)
        echo "$*" >> "$CALLS"
        case "$*" in
            *check_name=build*) if [ -n "${BUILD_RUNS:-}" ]; then jq -r "${@: -1}" <<< "$BUILD_RUNS"; else echo "$BUILD"; fi ;;
            *check_name=design*) echo "$DESIGN" ;;
            *check_name=leaks*) echo "$LEAKS" ;;
            *check_name=proof*) echo "$PROOF" ;;
            *) echo none ;;
        esac ;;
    *statuses*)
        if [ "$LOCAL_BUILD" = success ]; then
            printf '{"id":1,"url":"https://api.github.com/repos/kaczordodgers/notchcast/statuses/%s","state":"success"}\n' "$HEAD_SHA"
        fi ;;
    *variable\ get\ LANDING_HOLD*)
        [ -z "${HOLD_ERROR:-}" ] || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
        ! rm "$STORE.fail-next-get" 2>/dev/null || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
        [ -s "$STORE" ] || { echo 'variable LANDING_HOLD was not found' >&2; exit 1; }
        cat "$STORE" ;;
    *variable\ set\ LANDING_HOLD*)
        echo "set ${*: -1}" >> "$HOLD_LOG"; echo "${*: -1}" > "$STORE"
        [ -z "${HOLD_ERROR_AFTER_SET:-}" ] || touch "$STORE.fail-next-get" ;;
    *variable\ delete\ LANDING_HOLD*) echo delete >> "$HOLD_LOG"; rm -f "$STORE" ;;
    *) exit 3 ;;
esac
STUB
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
case "$1" in
    fetch|cat-file) exit 0 ;;
    worktree) exit 0 ;;
    push) echo 'unexpected push' >&2; exit 99 ;;
    merge-base) echo fixture-base; exit 0 ;;
    diff) printf '%s\0' "${CHANGED_PATH:-unrelated.txt}"; exit 0 ;;
    rev-parse)
        if [ "$2" = origin/main ]; then
            cp "$STORE" "$HELD_AT_MERGE" 2>/dev/null
            [ -z "${REPLACE_WITH:-}" ] || echo "$REPLACE_WITH" > "$STORE"
            echo 'REACHED_MERGE' >&2; exit 77
        fi ;;
esac
exec "$REAL_GIT" "$@"
STUB
chmod +x "$scratch/bin/gh" "$scratch/bin/git"
export REAL_GIT=$(command -v git)
cd "$scratch/repo"
git init -q
# Its own home, so no machine's private.env (a land lock among its hooks) reaches the script.
export HOME="$scratch/home"
mkdir -p "$HOME"
export PATH="$scratch/bin:$PATH" HEAD_SHA=0123456789012345678901234567890123456789
# The script under test runs as is, not origin/main's copy.
export NOTCHCAST_LAND_TOOLS=test CALLS="$scratch/calls" BASE_NAME=main BUILD=success DESIGN=success LEAKS=success LOCAL_BUILD=none
export PROOF=none
export STORE="$scratch/store" HOLD_LOG="$scratch/hold-log" HELD_AT_MERGE="$scratch/held-at-merge"
run() {
    : > "$CALLS"
    : > "$HOLD_LOG"
    rm -f "$HELD_AT_MERGE"
    if [ -n "${HOLD:-}" ]; then echo "$HOLD" > "$STORE"; else rm -f "$STORE"; fi
    status=0
    bash notchcast/land.sh 1 > "$scratch/output" 2>&1 || status=$?
}
export BASE_NAME=topic
run
grep -q 'REFUSED:.*main' "$scratch/output" || { echo 'FAIL: non-main PR was accepted'; exit 1; }
echo 'PASS: non-main base refused'
export BASE_NAME=main
for name in BUILD DESIGN LEAKS; do
    for verdict in failure pending; do
        export "$name=$verdict"
        run
        grep -qi "REFUSED:.*$name" "$scratch/output" || { echo "FAIL: $name $verdict accepted"; exit 1; }
        grep -q "commits/$HEAD_SHA/check-runs" "$CALLS"
        echo "PASS: $name $verdict refused on captured head"
    done
    export "$name=success"
done
for name in DESIGN LEAKS; do
    export "$name=none"
    run
    [ "$status" -eq 77 ] || { cat "$scratch/output"; echo "FAIL: absent $name refused"; exit 1; }
    echo "PASS: absent $name allowed"
    export "$name=success"
done
export BUILD=pending LOCAL_BUILD=success
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: local build lane refused'; exit 1; }
echo 'PASS: local build lane accepted'
export BUILD=success LOCAL_BUILD=none
run
[ "$status" -eq 77 ]
grep -q REACHED_MERGE "$scratch/output"
echo 'PASS: green checks reach merged-tree validation'
# Each argument is one build run, oldest first: "<conclusion>", or "pending" for one still running.
build_runs() {
    local i=0 conclusion
    BUILD_RUNS='{"check_runs":['
    for conclusion; do
        i=$((i + 1))
        [ "$i" -eq 1 ] || BUILD_RUNS+=,
        if [ "$conclusion" = pending ]; then
            BUILD_RUNS+="{\"app\":{\"slug\":\"github-actions\"},\"started_at\":\"2026-11-18T10:0$i:00Z\",\"status\":\"in_progress\",\"conclusion\":null}"
        else
            BUILD_RUNS+="{\"app\":{\"slug\":\"github-actions\"},\"started_at\":\"2026-11-18T10:0$i:00Z\",\"status\":\"completed\",\"conclusion\":\"$conclusion\"}"
        fi
    done
    export BUILD_RUNS+=']}'
}
for runs in 'success cancelled' 'success skipped' 'failure success cancelled'; do
    build_runs $runs
    run
    [ "$status" -eq 77 ] || { cat "$scratch/output"; echo "FAIL: build runs '$runs' refused"; exit 1; }
    echo "PASS: build runs '$runs' land: a cancelled or skipped run does not hide a green one"
done
for runs in 'success failure' 'success failure cancelled' 'success pending' 'cancelled' 'skipped cancelled'; do
    build_runs $runs
    run
    grep -q 'REFUSED: build is' "$scratch/output" || { cat "$scratch/output"; echo "FAIL: build runs '$runs' accepted"; exit 1; }
    echo "PASS: build runs '$runs' refused"
done
export BUILD_RUNS='{"check_runs":[{"id":200,"app":{"slug":"github-actions"},"started_at":"2026-11-18T10:00:00Z","status":"completed","conclusion":"failure"},{"id":100,"app":{"slug":"github-actions"},"started_at":"2026-11-18T10:00:00Z","status":"completed","conclusion":"success"}]}'
run
grep -q 'REFUSED: build is failure' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: same-second older green run hid a newer failure'; exit 1; }
echo 'PASS: a same-second tie goes to the newer run id'
unset BUILD_RUNS
export CHANGED_PATH=Tinycast/Fixture/Proved.swift
for verdict in none pending failure cancelled; do
    export PROOF=$verdict
    run
    grep -q "REFUSED: real-app proof (fixture-proof) is $verdict" "$scratch/output"
    grep -q "commits/$HEAD_SHA/check-runs?check_name=proof" "$CALLS"
    echo "PASS: declared path with proof $verdict refused on captured head"
done
export PROOF=success
run
[ "$status" -eq 77 ]
echo 'PASS: declared path with successful proof reaches merge'
export CHANGED_PATH=unrelated.txt PROOF=none
run
[ "$status" -eq 77 ]
! grep -q check_name=proof "$CALLS"
echo 'PASS: undeclared path needs no proof'
later=$(($(date +%s) + 600))
export HOLD=
before=$(date +%s)
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: no hold refused'; exit 1; }
read -r owner until auto lander < "$HELD_AT_MERGE" || { echo 'FAIL: no landing hold taken at the start'; exit 1; }
[ "$owner" = 1 ] && [ "$auto" = auto ] && [ "$until" -ge $((before + 9000)) ] && [ "$until" -le $(($(date +%s) + 9000)) ] \
    || { echo "FAIL: took '$owner $until $auto'"; exit 1; }
[ ! -e "$STORE" ] && [ "$(sed -n 2p "$HOLD_LOG")" = delete ] || { cat "$HOLD_LOG"; echo 'FAIL: the hold was not released at exit'; exit 1; }
echo 'PASS: land.sh takes an auto hold for its PR at the start and releases it at exit'
NOTCHCAST_LAND_HOLD_MINUTES=5 run
read -r owner until auto lander < "$HELD_AT_MERGE"
[ "$until" -le $(($(date +%s) + 300)) ] || { echo 'FAIL: NOTCHCAST_LAND_HOLD_MINUTES ignored'; exit 1; }
echo 'PASS: NOTCHCAST_LAND_HOLD_MINUTES sets the auto hold length'
export BUILD=failure
run
grep -q 'REFUSED: build is failure' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: build failure accepted'; exit 1; }
[ ! -e "$STORE" ] && [ "$(sed -n 2p "$HOLD_LOG")" = delete ] || { cat "$HOLD_LOG"; echo 'FAIL: the hold outlived a later refusal'; exit 1; }
export BUILD=success
echo 'PASS: a later refusal releases the hold'
export HOLD="330 $later"
run
grep -q 'REFUSED: landing is held for 330 until' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: a hold for another PR was ignored'; exit 1; }
! grep -q check-runs "$CALLS"
[ "$(cat "$STORE")" = "$HOLD" ] && [ ! -s "$HOLD_LOG" ] || { cat "$HOLD_LOG"; echo 'FAIL: a foreign hold was touched'; exit 1; }
echo 'PASS: a hold for another PR refuses before any check and is left alone'
export HOLD="330 $later auto"
run
grep -q 'REFUSED: landing is held for 330 until' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: a foreign auto hold was ignored'; exit 1; }
echo 'PASS: a foreign auto hold refuses'
export HOLD="1 $later"
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: the hold owner PR was refused'; exit 1; }
[ "$(cat "$STORE")" = "$HOLD" ] && [ ! -s "$HOLD_LOG" ] || { cat "$HOLD_LOG"; echo 'FAIL: the owner took or released its own hold'; exit 1; }
echo 'PASS: the PR that owns the hold lands and takes nothing'
export HOLD="strings $later"
NOTCHCAST_LAND_AS=strings run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: the named hold owner was refused'; exit 1; }
[ ! -s "$HOLD_LOG" ] || { cat "$HOLD_LOG"; echo 'FAIL: the named owner took a hold'; exit 1; }
echo 'PASS: NOTCHCAST_LAND_AS owner lands'
export HOLD=
REPLACE_WITH="330 $later" run
[ "$status" -eq 77 ] && [ "$(cat "$STORE")" = "330 $later" ] && ! grep -q delete "$HOLD_LOG" \
    || { cat "$HOLD_LOG"; echo 'FAIL: a hold replaced during the run was released'; exit 1; }
echo 'PASS: a hold replaced during the run is not released'
export HOLD="330 $(($(date +%s) - 1))"
run
[ "$status" -eq 77 ] || { cat "$scratch/output"; echo 'FAIL: an expired hold still refused'; exit 1; }
echo 'PASS: an expired hold is ignored'
export HOLD= HOLD_ERROR=1
run
grep -q 'REFUSED: cannot read the landing hold' "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: an unreadable hold was ignored'; exit 1; }
echo 'PASS: an unreadable hold refuses'
export HOLD_ERROR=
HOLD_ERROR_AFTER_SET=1 run
grep -q 'REFUSED: cannot read the landing hold' "$scratch/output" && [ ! -e "$STORE" ] && grep -q '^delete$' "$HOLD_LOG" \
    || { cat "$scratch/output" "$HOLD_LOG"; echo 'FAIL: a claim that failed its read-back left the hold behind'; exit 1; }
echo 'PASS: a claim that failed its read-back is released at exit'
for bad in '330' "330 $later extra" '330 later' '330 1e9' "330 0$later"; do
    export HOLD="$bad" HOLD_ERROR=
    run
    grep -q 'REFUSED: malformed landing hold' "$scratch/output" || { cat "$scratch/output"; echo "FAIL: malformed hold '$bad' was ignored"; exit 1; }
done
echo 'PASS: a malformed hold refuses'

# The land lease (#1161): private.env names a stub lock hook that logs each call and refuses while LOCK_EXIT is 1.
cat > "$scratch/bin/land-lock" <<'STUB'
#!/bin/bash
echo "$*" >> "$LOCK_LOG"
[ "${LOCK_EXIT:-0}" -eq 0 ] || { echo 'gate: land is held by queue@other until 12:00' >&2; exit 1; }
STUB
chmod +x "$scratch/bin/land-lock"
export HOLD= LOCK_LOG="$scratch/lock-log"
mkdir -p "$HOME/.config/notchcast"
echo 'NOTCHCAST_LAND_LOCK="land-lock land"' > "$HOME/.config/notchcast/private.env"
in_pty() { python3 -c 'import os, pty, sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))' "$@" < /dev/null; }
refused_by_lease() { grep -q "^REFUSED: landing is the queue's: sign off the PR and wait" "$scratch/output"; }
: > "$LOCK_LOG"
run < /dev/null
[ "$status" -eq 1 ] && refused_by_lease && [ ! -s "$LOCK_LOG" ] && [ ! -s "$CALLS" ] && [ ! -s "$HOLD_LOG" ] \
    || { cat "$scratch/output"; echo 'FAIL: a hand run under the lock hook was not refused before anything'; exit 1; }
echo 'PASS: with the lock hook a run without NOTCHCAST_LAND_LEASE is refused, never calls the hook and touches nothing'
: > "$LOCK_LOG"
NOTCHCAST_LAND_LEASE=queue@test LOCK_EXIT=1 run < /dev/null
[ "$status" -eq 1 ] && refused_by_lease && grep -q '^gate: land is held by queue@other until 12:00$' "$scratch/output" \
    && [ "$(cat "$LOCK_LOG")" = 'land take queue@test' ] && [ ! -s "$CALLS" ] \
    || { cat "$scratch/output"; echo 'FAIL: a lease the hook refused still landed'; exit 1; }
echo 'PASS: a lease the hook refuses is refused, with the holder the hook names'
: > "$LOCK_LOG"
NOTCHCAST_LAND_LEASE=queue@test run < /dev/null
[ "$status" -eq 77 ] && [ "$(cat "$LOCK_LOG")" = 'land take queue@test' ] \
    || { cat "$scratch/output"; echo 'FAIL: a taken lease did not land'; exit 1; }
echo 'PASS: a lease the hook grants lands'
: > "$LOCK_LOG"
NOTCHCAST_LAND_FORCE=1 run < /dev/null
[ "$status" -eq 1 ] && refused_by_lease && [ ! -s "$LOCK_LOG" ] || { cat "$scratch/output"; echo 'FAIL: a force without a terminal landed'; exit 1; }
status=0
NOTCHCAST_LAND_FORCE=1 in_pty bash notchcast/land.sh 1 > "$scratch/output" 2>&1 || status=$?
[ "$status" -eq 77 ] && grep -q '^FORCED: landing outside the queue' "$scratch/output" && [ ! -s "$LOCK_LOG" ] \
    || { cat "$scratch/output"; echo 'FAIL: a force from a terminal did not land'; exit 1; }
echo 'PASS: NOTCHCAST_LAND_FORCE=1 lands only from a terminal, saying FORCED, and never without one'
# train.sh refuses before it detaches, fetches or asks GitHub anything.
train() {
    : > "$CALLS"
    : > "$LOCK_LOG"
    status=0
    bash notchcast/train.sh "$@" > "$scratch/output" 2>&1 < /dev/null || status=$?
}
for args in '1 2' '--detach 1 2' '--queue' '--detach --queue'; do
    train $args
    [ "$status" -eq 1 ] && refused_by_lease && [ ! -s "$LOCK_LOG" ] && [ ! -s "$CALLS" ] && ! grep -q detached "$scratch/output" \
        || { cat "$scratch/output"; echo "FAIL: train.sh $args ran without a lease"; exit 1; }
    NOTCHCAST_LAND_LEASE=queue@test LOCK_EXIT=1 train $args
    [ "$status" -eq 1 ] && refused_by_lease && [ "$(cat "$LOCK_LOG")" = 'land take queue@test' ] && ! grep -q detached "$scratch/output" \
        || { cat "$scratch/output"; echo "FAIL: train.sh $args ran on a refused lease"; exit 1; }
    NOTCHCAST_LAND_FORCE=1 train $args
    [ "$status" -eq 1 ] && refused_by_lease && [ ! -s "$LOCK_LOG" ] || { cat "$scratch/output"; echo "FAIL: train.sh $args forced without a terminal"; exit 1; }
done
status=0
NOTCHCAST_LAND_FORCE=1 in_pty bash notchcast/train.sh --detach 1 > "$scratch/output" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q '^FORCED: landing outside the queue' "$scratch/output" && grep -q '^REFUSED: a forced train runs attached: drop --detach' "$scratch/output" \
    && ! grep -q detached "$scratch/output" || { cat "$scratch/output"; echo 'FAIL: a forced train detached'; exit 1; }
echo 'PASS: train.sh, --detach and --queue included, refuses without a lease, on a refused one and on a force without a terminal; a forced train never detaches'
