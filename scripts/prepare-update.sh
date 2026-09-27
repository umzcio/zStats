#!/bin/bash
# Package an already signed and notarized build. This never uploads or publishes.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 || "$1" != https://*/ ]]; then
    printf 'Usage: bash scripts/prepare-update.sh https://HOST/path/to/downloads/\n' >&2
    exit 1
fi
APP="$PWD/dist/zStats.app"
PLIST="$APP/Contents/Info.plist"
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
ACCOUNT="${ZSTATS_SPARKLE_KEY_ACCOUNT:-dev.zach.zStats}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST" > /dev/null
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")
# Refuse to prepare updates signed by a different key than the one embedded in the app.
KEYCHAIN_PUBLIC_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
if [[ "$PUBLIC_KEY" != "$KEYCHAIN_PUBLIC_KEY" ]]; then
    printf 'The Sparkle key in Keychain does not match the app’s public key.\n' >&2
    exit 1
fi
codesign --verify --deep --strict "$APP"
spctl --assess --type execute "$APP"
xcrun stapler validate "$APP"
OUTPUT="$PWD/dist/updates"
ARCHIVE="$OUTPUT/zStats-$VERSION-$BUILD.zip"
mkdir -p "$OUTPUT"
if [[ -e "$ARCHIVE" ]]; then
    printf 'Archive already exists; use a new build number: %s\n' "$ARCHIVE" >&2
    exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
"$TOOLS/generate_appcast" --account "$ACCOUNT" --download-url-prefix "$1" \
    --maximum-deltas 0 --embed-release-notes -o "$OUTPUT/appcast.xml" "$OUTPUT"
printf 'Prepared %s and signed appcast.xml. Nothing has been published.\n' "$ARCHIVE"
