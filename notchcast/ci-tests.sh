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
if [ "${RUNNER_ENVIRONMENT:-}" != github-hosted ]; then unset CI_SKIP_TESTS; fi
# The queue filter in notchcast/test-harnesses.sh reads NOTCHCAST_ONLY_TESTS, NOTCHCAST_SHARD and CI_SKIP_TESTS.
if [ -n "${NOTCHCAST_SWIFTC_CACHE:-}" ]; then
  # The swiftc already on PATH, not the toolchain's binary: xcrun's shim is what supplies the SDK.
  NOTCHCAST_SWIFTC_REAL=$(command -v swiftc)
  NOTCHCAST_SWIFTC_TOOLCHAIN="$("$NOTCHCAST_SWIFTC_REAL" --version 2>&1) $(xcrun --show-sdk-path) $(xcrun --show-sdk-version) $(sw_vers -buildVersion)"
  export NOTCHCAST_SWIFTC_REAL NOTCHCAST_SWIFTC_TOOLCHAIN
  mkdir -p "$NOTCHCAST_SWIFTC_CACHE" "$RUNNER_TEMP/swiftc-shim"
  ln -sf "$TOOLS/notchcast/swiftc-cache.py" "$RUNNER_TEMP/swiftc-shim/swiftc"
  export PATH="$RUNNER_TEMP/swiftc-shim:$PATH"
fi
status=0
./Scripts/run-tests.sh || status=$?
BIN="${TMPDIR:-/tmp}/tinycast-harness"
# A red harness is always red; the one escape is a reasoned entry in config.env.
exempt="" unreasoned=0
IFS=';' read -ra entries <<< "${UPSTREAM_RED_HARNESSES:-}"
for entry in ${entries[@]+"${entries[@]}"}; do
  [[ $entry =~ ^[[:space:]]*$ ]] && continue
  if [[ $entry =~ ^[[:space:]]*([A-Za-z0-9_.+-]+):[[:space:]]*([^[:space:]].*)$ ]]; then
    exempt="$exempt ${BASH_REMATCH[1]}"
    echo "::warning::EXEMPT ${BASH_REMATCH[1]}: its failure does not fail CI (UPSTREAM_RED_HARNESSES: ${BASH_REMATCH[2]})"
  else
    echo "::error::UPSTREAM_RED_HARNESSES entry without a reason: '$entry'"; unreasoned=1
  fi
done
failed=""
for f in "$BIN"/*.failed; do [ ! -e "$f" ] || failed="$failed $(basename "$f" .failed)"; done
if [ -n "$failed" ]; then
  for name in $failed; do cat "$BIN/$name.log"; done
  if [ -z "${UPSTREAM:-}" ]; then
    bash "$TOOLS/notchcast/fetch-upstream.sh" --no-tags
    UPSTREAM=$(git merge-base HEAD refs/remotes/upstream/main)
  fi
  # Diagnosis only: whatever upstream does, the verdict above stands.
  git worktree add -q --detach "$RUNNER_TEMP/pristine" "$UPSTREAM"
  for name in $failed; do
    if [ ! -e "$RUNNER_TEMP/pristine/Tests/$name.swift" ]; then
      echo "::error::$name fails; it does not exist on upstream ${UPSTREAM:0:7}"
    elif (cd "$RUNNER_TEMP/pristine" && TMPDIR="$RUNNER_TEMP/pristine-tmp" && mkdir -p "$TMPDIR" && export TMPDIR \
        && ./Scripts/run-tests.sh "$name" >/dev/null 2>&1); then
      echo "::error::$name fails; it passes on upstream ${UPSTREAM:0:7}"
    else
      echo "::error::$name fails; it also fails on upstream ${UPSTREAM:0:7}"
    fi
  done
  git worktree remove --force "$RUNNER_TEMP/pristine"
fi
blocking=""
for name in $failed; do
  case " $exempt " in
    *" $name "*) echo "::warning::EXEMPT $name is red and listed in UPSTREAM_RED_HARNESSES, so it does not fail CI" ;;
    *) blocking="$blocking $name" ;;
  esac
done
# Only a run whose every failure is exempt turns green; a harness still marked running never finished.
if [ "$status" -ne 0 ] && [ -n "$failed" ] && [ -z "$blocking" ]; then status=0; fi
[ "$unreasoned" -eq 0 ] || status=1
for marker in "$BIN"/*.running; do
  [ ! -e "$marker" ] || { echo "::error::$(basename "$marker" .running) never finished"; status=1; }
done
# run-tests.sh shows a green harness's SKIP nowhere else.
grep -h '^SKIP:' "$BIN"/*.log 2>/dev/null | sed 's/^/::notice::/' || true
exit $status
