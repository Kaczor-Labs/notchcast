#!/bin/bash
# Sign an ad-hoc signed app with a real identity from the inside out, as Xcode does: every nested code item keeps
# its identifier and entitlements and gets the hardened runtime. Runs none of the app's code, so the release job
# that holds the certificate signs a bundle a job without secrets built (notchcast/actions/sign).
# Usage: sign-app.sh <app> <identity> [<keychain>]   (keychain: search only it for the identity)
set -euo pipefail
APP=${1:?usage: sign-app.sh <app> <identity> [<keychain>]}
IDENTITY=${2:?usage: sign-app.sh <app> <identity> [<keychain>]}
FLAGS=(--force --sign "$IDENTITY" --timestamp=none --options runtime --preserve-metadata=identifier,entitlements)
[ -z "${3:-}" ] || FLAGS+=(--keychain "$3")
entitlements() { codesign -d --entitlements - --xml "$1" 2>/dev/null || true; }
sign() {
    local before
    before="$(entitlements "$1")"
    codesign "${FLAGS[@]}" "$1"
    [ "$(entitlements "$1")" = "$before" ] || { echo "::error::${1#"$APP/"}: entitlements changed when signed" >&2; exit 1; }
}
is_macho() { [ -f "$1" ] && [ ! -L "$1" ] && [[ "$(file -b "$1")" == Mach-O* ]]; }
# -depth lists a bundle's contents before the bundle; a bundle's main executable is signed with its bundle.
while IFS= read -r -d '' ITEM; do
    if [ -d "$ITEM" ] && { [ -d "$ITEM/Contents/MacOS" ] || [[ "$ITEM" == *.framework ]]; }; then
        sign "$ITEM"
    elif [[ "$ITEM" != */Contents/MacOS/* ]] && is_macho "$ITEM"; then
        sign "$ITEM"
    fi
done < <(find "$APP/Contents" -mindepth 1 -depth -print0)
sign "$APP"
# Nothing ad-hoc is left behind: every Mach-O in the bundle names the identity and has the hardened runtime.
while IFS= read -r -d '' ITEM; do
    is_macho "$ITEM" || continue
    INFO="$(codesign -dvv "$ITEM" 2>&1)"
    grep -qxF "Authority=$IDENTITY" <<< "$INFO" || { echo "::error::${ITEM#"$APP/"} is not signed by $IDENTITY" >&2; exit 1; }
    [[ "$INFO" =~ flags=0x[0-9a-f]+\([^\)]*runtime ]] || { echo "::error::${ITEM#"$APP/"} lacks the hardened runtime" >&2; exit 1; }
done < <(find "$APP" -type f -print0)
echo "signed $(basename "$APP") and its nested code with $IDENTITY"
