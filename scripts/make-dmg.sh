#!/bin/bash
# Package a built app with an Applications shortcut. No publishing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/zStats.app"
[[ -d "$APP" ]] || { printf 'Build dist/zStats.app first.\n' >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
DMG="$ROOT/dist/zStats-$VERSION-$BUILD.dmg"
[[ ! -e "$DMG" ]] || { printf 'Refusing to overwrite %s; move it aside or increase the build number.\n' "$DMG" >&2; exit 1; }
STAGE="$(mktemp -d "$ROOT/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/zStats.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname zStats -srcfolder "$STAGE" -format UDZO "$DMG"
if [[ -n "${ZSTATS_SIGNING_IDENTITY:-}" && "$ZSTATS_SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$ZSTATS_SIGNING_IDENTITY" --timestamp "$DMG"
    codesign --verify --strict "$DMG"
fi
printf 'Created %s\n' "$DMG"
