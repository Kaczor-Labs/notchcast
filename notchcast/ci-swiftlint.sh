#!/bin/bash
# Pinned SwiftLint for CI, checked against its SHA-256 before use; sourced, it puts swiftlint first on PATH.
set -euo pipefail
VERSION=0.65.1
SHA256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
DIR="$RUNNER_TEMP/swiftlint-$VERSION"
if [ ! -x "$DIR/swiftlint" ]; then
    curl -sSfLo "$RUNNER_TEMP/swiftlint.zip" "https://github.com/realm/SwiftLint/releases/download/${VERSION}/portable_swiftlint.zip"
    echo "$SHA256  $RUNNER_TEMP/swiftlint.zip" | shasum -a 256 -c -
    unzip -q -o "$RUNNER_TEMP/swiftlint.zip" -d "$DIR"
fi
export PATH="$DIR:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then echo "$DIR" >> "$GITHUB_PATH"; fi
