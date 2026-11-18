#!/bin/bash
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")" && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
printf '%s\n' '#!/bin/bash' 'echo "✗ App: not signed with a timestamped Developer ID" >&2' 'exit 1' > "$TEMP/upstream.sh"
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"
echo 'PASS: Developer ID failure is allowed'
printf '%s\n' '#!/bin/bash' 'echo "✗ App: not signed with a timestamped Developer ID"' 'echo "✗ App: seal does not verify"' 'exit 1' > "$TEMP/upstream.sh"
if bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"; then
    echo 'FAIL: other signature failure was accepted' >&2
    exit 1
fi
echo 'PASS: other signature failures are enforced'
printf '%s\n' '#!/bin/bash' 'exit 2' > "$TEMP/upstream.sh"
if bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"; then
    echo 'FAIL: silent upstream failure was accepted' >&2
    exit 1
fi
echo 'PASS: silent upstream failure is enforced'
printf '%s\n' '#!/bin/bash' 'exit 1' > "$TEMP/upstream.sh"
if bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"; then
    echo 'FAIL: silent exit 1 was accepted' >&2
    exit 1
fi
echo 'PASS: silent exit 1 is enforced'
printf '%s\n' '#!/bin/bash' 'echo "✓ App signature verified"' 'exit 0' > "$TEMP/upstream.sh"
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh"
echo 'PASS: successful upstream verification is accepted'
FAILURES=0
printf '%s\n' '#!/bin/bash' 'echo "✗ App: not signed with a timestamped Developer ID"' 'exit 3' > "$TEMP/upstream.sh"
STATUS=0
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh" || STATUS=$?
if [ "$STATUS" -eq 3 ]; then
    echo 'PASS: Developer ID line plus exit 3 preserves failure status'
else
    echo "FAIL: Developer ID line plus exit 3 returned $STATUS" >&2
    FAILURES=$((FAILURES + 1))
fi
printf '%s\n' '#!/bin/bash' 'set -u' 'unset MISSING' 'echo "✗ App: not signed with a timestamped Developer ID"' 'echo "$MISSING"' > "$TEMP/upstream.sh"
STATUS=0
bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh" || STATUS=$?
if [ "$STATUS" -eq 1 ]; then
    echo 'PASS: Developer ID line plus unbound-variable abort preserves failure status'
else
    echo "FAIL: Developer ID line plus unbound-variable abort returned $STATUS" >&2
    FAILURES=$((FAILURES + 1))
fi
ICLOUD_LINES=('echo "✗ App.app: no embedded provisioning profile"' 'echo "✗ App.app: its iCloud container is not iCloud.app.example"' 'echo "✗ App.app: iCloud is not set to Production"' 'echo "✗ App.app: push is not set to production"')
mkdir "$TEMP/bin"
printf '%s\n' '#!/bin/bash' 'printf "%s" "$FAKE_ENTITLEMENTS"' > "$TEMP/bin/codesign"
chmod +x "$TEMP/bin/codesign"
expect() {
    local WANT=$1 NAME=$2 ENTITLEMENTS=$3 STATUS=0
    shift 3
    printf '%s\n' '#!/bin/bash' "$@" 'exit 1' > "$TEMP/upstream.sh"
    PATH="$TEMP/bin:$PATH" FAKE_ENTITLEMENTS=$ENTITLEMENTS bash "$TOOLS/verify-signature.sh" "$TEMP/App.app" "$TEMP/upstream.sh" >/dev/null || STATUS=$?
    if [ "$STATUS" -eq "$WANT" ]; then echo "PASS: $NAME"; else echo "FAIL: $NAME returned $STATUS" >&2; FAILURES=$((FAILURES + 1)); fi
}
expect 0 'iCloud lines without iCloud entitlements are allowed' '' "${ICLOUD_LINES[@]}"
expect 1 'iCloud lines plus another failure are enforced' '' "${ICLOUD_LINES[@]}" 'echo "✗ App.app: the seal does not verify"'
expect 1 'iCloud lines with an iCloud entitlement are enforced' '<key>com.apple.developer.icloud-container-identifiers</key>' "${ICLOUD_LINES[@]}"
expect 1 'iCloud lines with a push entitlement are enforced' '<key>com.apple.developer.aps-environment</key>' "${ICLOUD_LINES[@]}"
# A real ad-hoc signed bundle, run through each upstream script named on the command line.
make_app() {
    local APP=$TEMP/real/Notchcast.app HELPER
    rm -rf "$TEMP/real" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
    cp /usr/bin/true "$APP/Contents/MacOS/Notchcast"
    cp /usr/bin/true "$APP/Contents/Helpers/ClipboardTextHelper"
    cp /usr/bin/true "$APP/Contents/Helpers/FileIndexHelper"
    for HELPER in 'Notchcast Dictation' 'Tinycast Dictation'; do
        mkdir -p "$APP/Contents/Helpers/$HELPER.app/Contents/MacOS"
        cp /usr/bin/true "$APP/Contents/Helpers/$HELPER.app/Contents/MacOS/$HELPER"
        plutil -create xml1 "$APP/Contents/Helpers/$HELPER.app/Contents/Info.plist"
        plutil -insert CFBundleIdentifier -string app.example.dictation "$APP/Contents/Helpers/$HELPER.app/Contents/Info.plist"
        plutil -insert CFBundleExecutable -string "$HELPER" "$APP/Contents/Helpers/$HELPER.app/Contents/Info.plist"
        codesign -f -s - -o runtime "$APP/Contents/Helpers/$HELPER.app/Contents/MacOS/$HELPER"
        codesign -f -s - -o runtime -i app.example.dictation "$APP/Contents/Helpers/$HELPER.app"
    done
    plutil -create xml1 "$APP/Contents/Info.plist"
    plutil -insert CFBundleIdentifier -string app.example "$APP/Contents/Info.plist"
    plutil -insert CFBundleExecutable -string Notchcast "$APP/Contents/Info.plist"
    codesign -f -s - -o runtime "$APP/Contents/Helpers/ClipboardTextHelper" "$APP/Contents/Helpers/FileIndexHelper"
    codesign -f -s - -o runtime "$@" "$APP"
}
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.wrong</string></array></dict></plist>' > "$TEMP/icloud.plist"
for UPSTREAM in "${@:-$TOOLS/../Scripts/verify-signature.sh}"; do
    make_app 2>/dev/null
    STATUS=0
    bash "$TOOLS/verify-signature.sh" "$TEMP/real/Notchcast.app" "$UPSTREAM" >/dev/null 2>&1 || STATUS=$?
    if [ "$STATUS" -eq 0 ]; then echo "PASS: $UPSTREAM accepts an ad-hoc bundle"; else echo "FAIL: $UPSTREAM rejected an ad-hoc bundle ($STATUS)" >&2; FAILURES=$((FAILURES + 1)); fi
    grep -q 'iCloud container' "$UPSTREAM" || continue
    make_app --entitlements "$TEMP/icloud.plist" 2>/dev/null
    STATUS=0
    bash "$TOOLS/verify-signature.sh" "$TEMP/real/Notchcast.app" "$UPSTREAM" >/dev/null 2>&1 || STATUS=$?
    if [ "$STATUS" -ne 0 ]; then echo "PASS: $UPSTREAM with a wrong iCloud container"; else echo "FAIL: $UPSTREAM accepted a wrong iCloud container" >&2; FAILURES=$((FAILURES + 1)); fi
done
exit "$FAILURES"
