#!/bin/bash
set -euo pipefail
VERSION=2.46.0
if [ "$(uname)" = Linux ]; then
    # XcodeGen ships no Linux binary: build the pinned tag (5 min); actions/xcodegen caches the result.
    COMMIT=8445e778451c7e44237b90281bde622d764b0084
    export XCODEGEN="$RUNNER_TEMP/xcodegen/xcodegen/bin/xcodegen"
    case "$("$XCODEGEN" --version 2>/dev/null || true)" in
        *"$VERSION"*) ;;
        *)
            git clone -q --depth 1 --branch "$VERSION" https://github.com/yonaskolb/XcodeGen.git "$RUNNER_TEMP/xcodegen-src"
            test "$(git -C "$RUNNER_TEMP/xcodegen-src" rev-parse HEAD)" = "$COMMIT"
            swift build -c release --product xcodegen --static-swift-stdlib --package-path "$RUNNER_TEMP/xcodegen-src"
            # The release zip's layout: xcodegen reads its setting presets from ../share beside the binary.
            mkdir -p "$(dirname "$XCODEGEN")" "$RUNNER_TEMP/xcodegen/xcodegen/share/xcodegen"
            cp "$RUNNER_TEMP/xcodegen-src/.build/release/xcodegen" "$XCODEGEN"
            cp -R "$RUNNER_TEMP/xcodegen-src/SettingPresets" "$RUNNER_TEMP/xcodegen/xcodegen/share/xcodegen/"
            ;;
    esac
else
    SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
    curl -sSfLo "$RUNNER_TEMP/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip"
    echo "$SHA256  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -
    unzip -q -o "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP/xcodegen"
    export XCODEGEN="$RUNNER_TEMP/xcodegen/xcodegen/bin/xcodegen"
fi
if [ -n "${GITHUB_ENV:-}" ]; then echo "XCODEGEN=$XCODEGEN" >> "$GITHUB_ENV"; fi
