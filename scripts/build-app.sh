#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
APP="$PWD/dist/zStats.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/zStats" "$APP/Contents/MacOS/zStats"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
ICON_BUILD="$PWD/.build/composer-icon"
mkdir -p "$ICON_BUILD"
xcrun actool "$PWD/assets/brand/zStats.icon" \
    --compile "$ICON_BUILD" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon zStats --output-partial-info-plist "$ICON_BUILD/partial-info.plist" \
    --output-format human-readable-text
cp "$ICON_BUILD/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$ICON_BUILD/zStats.icns" "$APP/Contents/Resources/zStats.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>zStats</string>
<key>CFBundleDisplayName</key><string>zStats</string>
<key>CFBundleIdentifier</key><string>dev.zach.zStats</string>
<key>CFBundleExecutable</key><string>zStats</string>
<key>CFBundleIconFile</key><string>zStats</string>
<key>CFBundleIconName</key><string>zStats</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>zStats — local system monitoring</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
