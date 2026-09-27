#!/bin/bash
# Package a built app in a branded drag-to-Applications window. No publishing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/zStats.app"
command -v create-dmg > /dev/null || { printf 'Install create-dmg first: brew install create-dmg\n' >&2; exit 1; }
[[ -d "$APP" ]] || { printf 'Build dist/zStats.app first.\n' >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
DMG="$ROOT/dist/zStats-$VERSION-$BUILD.dmg"
[[ ! -e "$DMG" ]] || { printf 'Refusing to overwrite %s; move it aside or increase the build number.\n' "$DMG" >&2; exit 1; }
STAGE="$(mktemp -d "$ROOT/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/zStats.app"
ARTWORK="$ROOT/.build/dmg-artwork"
mkdir -p "$ARTWORK"
swift "$ROOT/scripts/render-dmg-background.swift" "$ARTWORK/background.png"
create-dmg \
    --volname "Install zStats" \
    --volicon "$APP/Contents/Resources/zStats.icns" \
    --background "$ARTWORK/background.png" \
    --window-pos 240 180 --window-size 720 468 \
    --icon-size 112 --text-size 14 \
    --icon "zStats.app" 200 218 --hide-extension "zStats.app" \
    --app-drop-link 520 218 \
    --format UDZO --filesystem HFS+ --no-internet-enable \
    "$DMG" "$STAGE"
if [[ -n "${ZSTATS_SIGNING_IDENTITY:-}" && "$ZSTATS_SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$ZSTATS_SIGNING_IDENTITY" --timestamp "$DMG"
    codesign --verify --strict "$DMG"
fi
printf 'Created %s\n' "$DMG"
