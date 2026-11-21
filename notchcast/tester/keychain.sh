#!/bin/bash
# Hosted tester scenario: the app's KeychainSecretStore against a job-local keychain, the login keychain out of reach.
set -euo pipefail
OUT=${OUT:?}
[ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] || { echo "keychain.sh replaces the user's keychain list: GitHub-hosted runner only" >&2; exit 2; }
mkdir -p "$OUT"
exec > >(tee -a "$OUT/keychain.log") 2>&1
kc="$RUNNER_TEMP/tester.keychain-db"
pw=$(uuidgen)
echo "search list before: $(security list-keychains -d user | xargs)"
security create-keychain -p "$pw" "$kc"
# No lock timeout, unlocked now: nothing can ask for its password later.
security set-keychain-settings "$kc"
security unlock-keychain -p "$pw" "$kc"
# The login keychain left in the search list hung the spike's run for 17 min on a prompt nobody could answer.
security list-keychains -d user -s "$kc"
security default-keychain -d user -s "$kc"
list=$(security list-keychains -d user | xargs)
echo "search list now: $list"
case "$list" in *login.keychain*) echo "FAIL login keychain still in the search list"; exit 1 ;; esac
swiftc -swift-version 6 -parse-as-library -o "$RUNNER_TEMP/keychain-probe" "$(dirname "$0")/keychain-probe.swift" Tinycast/Platform/KeychainSecretStore.swift
"$RUNNER_TEMP/keychain-probe" | tee "$RUNNER_TEMP/keychain-probe.out"
account=$(sed -n 's/^account: //p' "$RUNNER_TEMP/keychain-probe.out")
security find-generic-password -s app.notchcast.dev.tester -a "$account" "$kc" | grep -E '^keychain:|"svce"|"acct"'
echo "PASS item stored in the job keychain"
