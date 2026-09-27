#!/bin/bash
# Build a signed, notarized app and DMG locally. Never creates a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="$PWD/scripts/.notary-config.local"
[[ -f "$CONFIG" ]] || { printf 'Missing scripts/.notary-config.local; see scripts/notary-config.example.\n' >&2; exit 1; }
source "$CONFIG"
: "${ZSTATS_SIGNING_IDENTITY:?Set ZSTATS_SIGNING_IDENTITY in the local notarization config}"
[[ "$ZSTATS_SIGNING_IDENTITY" != "-" ]] || { printf 'Release builds require a Developer ID identity.\n' >&2; exit 1; }
export ZSTATS_SIGNING_IDENTITY
swift test --disable-sandbox
python3 scripts/test-release-config.py
bash scripts/build-app.sh
APP="$PWD/dist/zStats.app"
bash scripts/notarize.sh "$APP"
spctl --assess --type execute "$APP"
bash scripts/make-dmg.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
DMG="$PWD/dist/zStats-$VERSION-$BUILD.dmg"
bash scripts/notarize.sh "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
printf '\nReady: %s\nSigned and notarized. Nothing has been uploaded to GitHub.\n' "$DMG"
