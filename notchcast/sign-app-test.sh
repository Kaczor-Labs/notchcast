#!/bin/bash
# script-tests: macos (security keychains and codesign)
# sign-app.sh on a real ad-hoc signed fixture app (a tool helper and a nested helper app, each with its own
# entitlements), signed with a throwaway self-signed identity in a temporary keychain.
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
KEYCHAIN="$WORK/test.keychain-db"
SEARCH=$(security list-keychains -d user | sed 's/"//g')
cleanup() {
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    # shellcheck disable=SC2086
    security list-keychains -d user -s $SEARCH
    rm -rf "$WORK"
}
trap cleanup EXIT
IDENTITY="Notchcast Sign Test $$"
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 2 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/cert.p12" -passout pass:test
SHA1=$(/usr/bin/openssl x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
security create-keychain -p test "$KEYCHAIN"
security unlock-keychain -p test "$KEYCHAIN"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P test -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k test "$KEYCHAIN" >/dev/null

APP="$WORK/Fixture.app"
plist() { printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>%s</dict></plist>\n' "$1"; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers/Inner.app/Contents/MacOS"
plist '<key>CFBundleIdentifier</key><string>app.fixture</string><key>CFBundleExecutable</key><string>Fixture</string>' \
    > "$APP/Contents/Info.plist"
plist '<key>CFBundleIdentifier</key><string>app.fixture.inner</string><key>CFBundleExecutable</key><string>Inner</string>' \
    > "$APP/Contents/Helpers/Inner.app/Contents/Info.plist"
echo 'int main(void) { return 0; }' > "$WORK/main.c"
for BIN in MacOS/Fixture Helpers/Tool Helpers/Inner.app/Contents/MacOS/Inner; do
    cc -o "$APP/Contents/$BIN" "$WORK/main.c"
done
plist '<key>com.apple.security.device.audio-input</key><true/>' > "$WORK/inner.entitlements"
plist '<key>com.apple.security.cs.disable-library-validation</key><true/>' > "$WORK/tool.entitlements"
plist '<key>com.apple.security.automation.apple-events</key><true/>' > "$WORK/app.entitlements"
codesign --force --sign - -i app.fixture.tool --entitlements "$WORK/tool.entitlements" "$APP/Contents/Helpers/Tool"
codesign --force --sign - --entitlements "$WORK/inner.entitlements" "$APP/Contents/Helpers/Inner.app"
codesign --force --sign - --entitlements "$WORK/app.entitlements" "$APP"

bash "$TOOLS/sign-app.sh" "$APP" "$IDENTITY" "$KEYCHAIN"
codesign --verify --deep --strict -R="certificate leaf = H\"$SHA1\"" "$APP"
echo 'PASS: the app and its nested code verify against the leaf pin'
for PAIR in Helpers/Tool=app.fixture.tool=disable-library-validation Helpers/Inner.app=app.fixture.inner=audio-input \
    .=app.fixture=apple-events; do
    IFS='=' read -r ITEM ID ENTITLEMENT <<< "$PAIR"
    TARGET="$APP/Contents/$ITEM"; [ "$ITEM" != . ] || TARGET="$APP"
    INFO=$(codesign -dvv "$TARGET" 2>&1)
    grep -qx "Identifier=$ID" <<< "$INFO" || { echo "FAIL: $ITEM lost its identifier"; exit 1; }
    ENTITLEMENTS=$(codesign -d --entitlements - --xml "$TARGET" 2>/dev/null)
    grep -q "$ENTITLEMENT" <<< "$ENTITLEMENTS" || { echo "FAIL: $ITEM lost its entitlements"; exit 1; }
done
echo 'PASS: identifiers and entitlements survive, item by item'
if bash "$TOOLS/sign-app.sh" "$APP" "Nobody $$" "$KEYCHAIN" 2>/dev/null; then
    echo 'FAIL: signing with a missing identity succeeded'; exit 1
fi
echo 'PASS: a missing identity fails the signing'
