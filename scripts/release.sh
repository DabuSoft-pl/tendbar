#!/bin/bash
# Builds a Developer ID signed, notarized and stapled Tendbar.app and a DMG with it in build/release.
#
# Needs a "Developer ID Application" certificate in the keychain and:
#   TEAM_ID         the 10-character Apple Developer team id
# and notarization credentials, either
#   NOTARY_PROFILE  a keychain profile saved with `xcrun notarytool store-credentials`
# or an App Store Connect API key:
#   NOTARY_KEY      path to the AuthKey_XXXXXXXXXX.p8 file
#   NOTARY_KEY_ID   its key id
#   NOTARY_ISSUER   its issuer id
# Optional:
#   KEYCHAIN        the keychain holding the certificate (CI uses a temporary one)
#   SKIP_NOTARIZE=1 sign only, for checking the signature without waiting for Apple
#   SIGN_IDENTITY   another identity; "-" signs ad hoc, for trying the script without a certificate
set -euo pipefail

cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to the Apple Developer team id}"
if [[ "${SKIP_NOTARIZE:-}" != 1 && -z "${NOTARY_PROFILE:-}" ]]; then
    : "${NOTARY_KEY:?Set NOTARY_PROFILE, or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER}"
    : "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
    : "${NOTARY_ISSUER:?Set NOTARY_ISSUER}"
fi

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
# A tag build must match the version in project.yml, so a release never ships under the wrong number.
if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_TYPE:-}" == tag && "$GITHUB_REF_NAME" != "v$VERSION" ]]; then
    echo "Tag $GITHUB_REF_NAME does not match MARKETING_VERSION $VERSION in project.yml" >&2
    exit 1
fi

IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
OUT=build/release
ARCHIVE=build/Tendbar.xcarchive
APP="$OUT/Tendbar.app"
DMG="$OUT/Tendbar-$VERSION.dmg"
SIGN_FLAGS=(--force --sign "$IDENTITY")
# Apple's timestamp server only signs real identities.
[[ "$IDENTITY" != - ]] && SIGN_FLAGS+=(--timestamp)
[[ -n "${KEYCHAIN:-}" ]] && SIGN_FLAGS+=(--keychain "$KEYCHAIN")

notarize() {
    if [[ "${SKIP_NOTARIZE:-}" == 1 ]]; then
        echo "Skipping notarization of $1"
        return
    fi
    local credentials
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        credentials=(--keychain-profile "$NOTARY_PROFILE")
    else
        credentials=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    fi
    xcrun notarytool submit "$1" "${credentials[@]}" --wait --timeout 30m
}

echo "Tendbar $VERSION ($BUILD), team $TEAM_ID"
rm -rf "$OUT" "$ARCHIVE"
mkdir -p "$OUT"

xcodegen generate --quiet
xcodebuild -project Tendbar.xcodeproj -scheme Tendbar -configuration Release -derivedDataPath build \
    -destination "generic/platform=macOS" -archivePath "$ARCHIVE" -quiet archive \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="${KEYCHAIN:+--keychain $KEYCHAIN}"
ditto "$ARCHIVE/Products/Applications/Tendbar.app" "$APP"

# Signed again outside Xcode: the helper inside first, then the app around it, both with the hardened runtime and a
# secure timestamp, which notarization requires.
codesign "${SIGN_FLAGS[@]}" --options runtime "$APP/Contents/MacOS/tendbar-hook"
codesign "${SIGN_FLAGS[@]}" --options runtime --entitlements Tendbar/Tendbar.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="$OUT/Tendbar-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
rm "$ZIP"
[[ "${SKIP_NOTARIZE:-}" == 1 ]] || xcrun stapler staple "$APP"

STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Tendbar.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Tendbar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
codesign "${SIGN_FLAGS[@]}" "$DMG"
notarize "$DMG"
if [[ "${SKIP_NOTARIZE:-}" != 1 ]]; then
    xcrun stapler staple "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Done: $DMG"
