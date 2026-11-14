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
# and the Sparkle EdDSA key that signs updates: from the login keychain (account "tendbar", made with
# `generate_keys --account tendbar`), or
#   SPARKLE_KEY_FILE  a file with the private key (`generate_keys --account tendbar -x <file>` exports it)
# Optional:
#   KEYCHAIN        the keychain holding the certificate (CI uses a temporary one)
#   SKIP_NOTARIZE=1 sign only, for checking the signature without waiting for Apple
#   SIGN_IDENTITY   another identity; "-" signs ad hoc, for trying the script without a certificate
#   DELTA_COUNT     how many earlier releases get a Sparkle delta update (default 2, 0 for none); needs `gh`
#   BETA=<n>        builds beta n of MARKETING_VERSION for the pre-release v<version>-beta.<n>: its appcast keeps the
#                   items of the latest release and adds this one on the `beta` channel, which only copies with
#                   "Receive beta versions" on look at. Needs `gh`. The end of the output says where each file goes.
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

BETA="${BETA:-}"
if [[ -n "$BETA" ]]; then
    [[ "$BETA" =~ ^[0-9]+$ ]] || { echo "BETA must be a number" >&2; exit 1; }
    TAG="v$VERSION-beta.$BETA"
    LABEL="$VERSION beta $BETA"
    FILE_VERSION="$VERSION-beta$BETA"
else
    TAG="v$VERSION"
    LABEL="$VERSION"
    FILE_VERSION="$VERSION"
fi

IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
OUT=build/release
ARCHIVE=build/Tendbar.xcarchive
APP="$OUT/Tendbar.app"
DMG="$OUT/Tendbar-$FILE_VERSION.dmg"
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

echo "Tendbar $LABEL ($BUILD), team $TEAM_ID"
rm -rf "$OUT" "$ARCHIVE"
mkdir -p "$OUT"

xcodegen generate --quiet
xcodebuild -project Tendbar.xcodeproj -scheme Tendbar -configuration Release -derivedDataPath build \
    -destination "generic/platform=macOS" -archivePath "$ARCHIVE" -quiet archive \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual TENDBAR_BETA="$BETA" \
    OTHER_CODE_SIGN_FLAGS="${KEYCHAIN:+--keychain $KEYCHAIN}"
ditto "$ARCHIVE/Products/Applications/Tendbar.app" "$APP"

# Signed again outside Xcode, inside out, with the hardened runtime and a secure timestamp, which notarization
# requires: Sparkle's helpers in the order its documentation gives, the hook helper, then the app around them.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_FLAGS[@]}" --options runtime "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" --options runtime --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" --options runtime "$SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_FLAGS[@]}" --options runtime "$SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_FLAGS[@]}" --options runtime "$SPARKLE"
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
hdiutil create -quiet -volname "Tendbar $LABEL" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
codesign "${SIGN_FLAGS[@]}" "$DMG"
notarize "$DMG"
if [[ "${SKIP_NOTARIZE:-}" != 1 ]]; then
    xcrun stapler staple "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

# The Sparkle feed for this release. It goes up with the DMG, and the app reads the copy on the latest published
# release, so CURRENT_PROJECT_VERSION has to grow with every release.
SPARKLE_BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin
sign_update() {
    if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
        "$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$1"
    else
        "$SPARKLE_BIN/sign_update" --account tendbar "$1"
    fi
}
ENCLOSURE=$(sign_update "$DMG")
REPO=https://github.com/DabuSoft-pl/tendbar

# Delta updates from the last published releases: a copy installed from one of them downloads only the
# difference (a few hundred kB instead of the whole DMG), and Sparkle falls back to the DMG when a delta does
# not apply. Each Tendbar<build>-<old build>.delta goes up with the release. A delta that fails only warns: the
# release is notarized by now and works without it.
make_delta() {
    local tag=$1 dir="$OUT/previous/$1"
    gh release download "$tag" --repo DabuSoft-pl/tendbar --pattern '*.dmg' --dir "$dir" || return 1
    mkdir -p "$dir/mount"
    diskutil image attach --nobrowse --readOnly --mountPoint "$dir/mount" "$dir"/*.dmg > /dev/null || return 1
    ditto "$dir/mount/Tendbar.app" "$dir/Tendbar.app"
    diskutil eject "$dir/mount" > /dev/null || return 1
    local old_build
    old_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$dir/Tendbar.app/Contents/Info.plist") || return 1
    [[ "$old_build" != "$BUILD" ]] || return 0
    local delta="$OUT/Tendbar$BUILD-$old_build.delta" signature
    "$SPARKLE_BIN/BinaryDelta" create "$dir/Tendbar.app" "$APP" "$delta" || return 1
    signature=$(sign_update "$delta") || return 1
    DELTAS+="
        <enclosure url=\"$REPO/releases/download/$TAG/$(basename "$delta")\" sparkle:deltaFrom=\"$old_build\" type=\"application/octet-stream\" $signature/>"
    echo "Delta from $tag (build $old_build): $(stat -f %z "$delta") bytes"
}

DELTAS=""
if (( ${DELTA_COUNT:-2} > 0 )) && command -v gh > /dev/null; then
    for PREVIOUS in $(gh release list --repo DabuSoft-pl/tendbar --exclude-drafts --exclude-pre-releases \
        --limit "${DELTA_COUNT:-2}" --json tagName --jq '.[].tagName' || true); do
        make_delta "$PREVIOUS" || echo "warning: no delta from $PREVIOUS" >&2
    done
    rm -rf "$OUT/previous"
fi
[[ -n "$DELTAS" ]] && DELTAS="
      <sparkle:deltas>$DELTAS
      </sparkle:deltas>"
MINIMUM=$(sed -n 's/^ *macOS: *"\(.*\)"/\1/p' project.yml)

# Every copy reads the appcast of the latest published release, so a beta goes into that file: the release's own
# items stay as they are, an older beta item is dropped, and this one is added on the beta channel.
EARLIER=""
CHANNEL=""
if [[ -n "$BETA" ]]; then
    LATEST=$(gh release view --repo DabuSoft-pl/tendbar --json tagName --jq .tagName)
    gh release download "$LATEST" --repo DabuSoft-pl/tendbar --pattern appcast.xml --output "$OUT/latest-appcast.xml"
    EARLIER=$'\n'$(awk '/<item>/ { item = ""; inside = 1 } inside { item = item $0 "\n" } /<\/item>/ {
        inside = 0; if (item !~ /<sparkle:channel>/) printf "%s", item }' "$OUT/latest-appcast.xml")
    rm "$OUT/latest-appcast.xml"
    [[ "$EARLIER" == *"<item>"* ]] || { echo "No items in the appcast of $LATEST" >&2; exit 1; }
    CHANNEL="
      <sparkle:channel>beta</sparkle:channel>"
fi
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tendbar</title>
    <link>$REPO</link>
    <item>
      <title>Tendbar $LABEL</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>$CHANNEL
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$LABEL</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO/releases/tag/$TAG</sparkle:fullReleaseNotesLink>
      <enclosure url="$REPO/releases/download/$TAG/$(basename "$DMG")" type="application/octet-stream" $ENCLOSURE/>$DELTAS
    </item>$EARLIER
  </channel>
</rss>
XML

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Done: $DMG"
if [[ -n "$BETA" ]]; then
    echo "Publish: the DMG, .sha256 and .delta files on the pre-release $TAG (gh release create --prerelease),"
    echo "then appcast.xml on $LATEST with gh release upload --clobber. Homebrew stays on $LATEST."
else
    echo "Publish: every file but Tendbar.app on the release $TAG, then the version and sha256 in the Homebrew cask."
fi
