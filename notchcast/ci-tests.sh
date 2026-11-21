#!/bin/bash
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")/.." && pwd)
export CI=1
export LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 NOTCHCAST_TEST_HELPER_EXECUTABLE=1
export TINYCAST_TEST_JOBS=${CHAD_BUILD_QUEUE_JOBS:-4}
set -a
# shellcheck disable=SC1091
source "$TOOLS/notchcast/config.env"
set +a
[ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] || unset CI_SKIP_TESTS
# The queue filter in notchcast/test-harnesses.sh reads NOTCHCAST_ONLY_TESTS, NOTCHCAST_SHARD and CI_SKIP_TESTS,
# and skips HOSTED_ONLY_TESTS itself on a runner that is neither GitHub-hosted nor isolated.
if [ -n "${NOTCHCAST_SWIFTC_CACHE:-}" ]; then
  # The swiftc already on PATH, not the toolchain's binary: xcrun's shim is what supplies the SDK.
  NOTCHCAST_SWIFTC_REAL=$(command -v swiftc)
  NOTCHCAST_SWIFTC_TOOLCHAIN="$("$NOTCHCAST_SWIFTC_REAL" --version 2>&1) $(xcrun --show-sdk-path) $(xcrun --show-sdk-version) $(sw_vers -buildVersion)"
  export NOTCHCAST_SWIFTC_REAL NOTCHCAST_SWIFTC_TOOLCHAIN
  mkdir -p "$NOTCHCAST_SWIFTC_CACHE" "$RUNNER_TEMP/swiftc-shim"
  ln -sf "$TOOLS/notchcast/swiftc-cache.py" "$RUNNER_TEMP/swiftc-shim/swiftc"
  export PATH="$RUNNER_TEMP/swiftc-shim:$PATH"
fi
if [ "$(uname -s)" = Darwin ]; then
  # A fresh VM session stays Light until a reboot; FormInputTests must render Dark, as the app.
  NOTCHCAST_DARK_OBJECT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/notchcast-dark.o"
  triple=$(swiftc -print-target-info | python3 -c 'import json, sys; print(json.load(sys.stdin)["target"]["triple"])')
  clang -fmodules -x objective-c -target "$triple" -c -o "$NOTCHCAST_DARK_OBJECT" - <<'OBJC'
@import AppKit;
__attribute__((constructor)) static void notchcastDark(void) {
  NSApplication.sharedApplication.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}
OBJC
  export NOTCHCAST_DARK_OBJECT
fi
# Harnesses that fail, one per line, for harness-select.py misses (pr.yml).
failures=${RUNNER_TEMP:+$RUNNER_TEMP/harness-failures}
record() { if [ -n "$failures" ]; then echo "$1" >> "$failures"; fi; }
if [ -n "$failures" ]; then : > "$failures"; fi
# Harnesses red here and on upstream too: ignored for the verdict, but this run proved none of them (pr.yml).
excused=${RUNNER_TEMP:+$RUNNER_TEMP/harness-excused}
if [ -n "$excused" ]; then : > "$excused"; fi
status=0
./Scripts/run-tests.sh || status=$?
BIN="${TMPDIR:-/tmp}/tinycast-harness"
if [ "$status" -ne 0 ] && ls "$BIN"/*.failed >/dev/null 2>&1; then
  failed="$(for f in "$BIN"/*.failed; do basename "$f" .failed; done)"
  # Written before the upstream comparison can fail, then narrowed to the harnesses that are ours.
  for name in $failed; do cat "$BIN/$name.log"; record "$name"; done
  if [ "$status" -ne 1 ]; then
    echo "::error::Suite exited $status before a trusted comparison. No harness failures were excused."
    exit "$status"
  fi
  if [ -z "${UPSTREAM:-}" ]; then
    bash "$TOOLS/notchcast/fetch-upstream.sh" --no-tags
    UPSTREAM=$(git merge-base HEAD refs/remotes/upstream/main)
  fi
  pristine="$RUNNER_TEMP/pristine"
  if [ -e "$pristine/.git" ]; then git worktree remove --force "$pristine"; fi
  git worktree prune --expire now
  git worktree add -q --detach "$pristine" "$UPSTREAM"
  trap 'git worktree remove --force "$pristine"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  status=0
  unexcused=""
  for name in $failed; do
    reason=""
    if [ ! -f "$pristine/Tests/$name.swift" ]; then
      reason="does not exist on upstream"
    elif ! cmp -s Scripts/run-tests.sh "$pristine/Scripts/run-tests.sh"; then
      reason="has a different runner script from pristine upstream"
    elif reason=$(python3 "$TOOLS/notchcast/harness_inputs.py" --compare-pristine "$pristine" "$name" 2>&1); then
      pristine_tmp=$(mktemp -d "$RUNNER_TEMP/pristine-tmp.XXXXXX")
      pristine_status=0
      (cd "$pristine" && TMPDIR="$pristine_tmp" ./Scripts/run-tests.sh "$name") > "$pristine_tmp/result" 2>&1 \
        || pristine_status=$?
      pristine_bin="$pristine_tmp/tinycast-harness/$name"
      if [ "$pristine_status" -eq 0 ]; then
        reason="passes on upstream ${UPSTREAM:0:7}"
      elif [ "$pristine_status" -ne 1 ] || [ ! -x "$pristine_bin" ] || [ ! -f "$pristine_bin.failed" ] \
          || ! awk -v name="$name" '
            /^\033\[31m--- / { exit }
            /^\[1\/1\] \033\[31mFAIL\033\[0m  / {
              assertion = (NF == 7 && $3 == name && $4 == "assertion" && $5 == "failed" &&
                           $6 == "after" && $7 ~ /^[0-9]+(\.[0-9]+)?s$/)
              exit
            }
            END { exit !assertion }
          ' "$pristine_tmp/result"; then
        cat "$pristine_tmp/result"
        reason="pristine upstream did not report a harness assertion failure (exit $pristine_status)"
      fi
    else
      reason=${reason:-"could not establish identical inputs"}
    fi
    if [ -n "$reason" ]; then
      echo "::error::$name fails with our commits and $reason. Failure was not excused."
      status=1
      unexcused="$unexcused$name"$'\n'
    else
      echo "::warning::$name fails on upstream ${UPSTREAM:0:7} too; not ours, ignored"
      if [ -n "$excused" ]; then echo "$name" >> "$excused"; fi
    fi
  done
  if [ -n "$failures" ]; then printf '%s' "$unexcused" > "$failures"; fi
fi
# run-tests.sh shows a green harness's SKIP nowhere else.
grep -h '^SKIP:' "$BIN"/*.log 2>/dev/null | sed 's/^/::notice::/' || true
exit $status
