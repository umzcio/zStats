#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
# Validate release metadata before doing expensive work.
python3 scripts/write-info-plist.py .build/zStats-Info.plist
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
APP="$PWD/dist/zStats.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/zStats" "$APP/Contents/MacOS/zStats"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp assets/brand/LICENSE "$APP/Contents/Resources/zStats-Artwork-LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp assets/licenses/Sparkle-LICENSE.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
SPARKLE="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
ICON_BUILD="$PWD/.build/composer-icon"
mkdir -p "$ICON_BUILD"
xcrun actool "$PWD/assets/brand/zStats.icon" \
    --compile "$ICON_BUILD" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon zStats --output-partial-info-plist "$ICON_BUILD/partial-info.plist" \
    --output-format human-readable-text
cp "$ICON_BUILD/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$ICON_BUILD/zStats.icns" "$APP/Contents/Resources/zStats.icns"
cp .build/zStats-Info.plist "$APP/Contents/Info.plist"
IDENTITY="${ZSTATS_SIGNING_IDENTITY:--}"
if [[ "$IDENTITY" != "-" ]]; then
    FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
    # Sign nested code inside out. Preserve Sparkle's helper entitlements.
    for component in "XPCServices/Downloader.xpc" "XPCServices/Installer.xpc" "Autoupdate" "Updater.app"; do
        codesign --force --sign "$IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$component"
    done
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$FRAMEWORK"
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
else
    # Local builds keep Sparkle's upstream signatures and use an ad-hoc host signature.
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
