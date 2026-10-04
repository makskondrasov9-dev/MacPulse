#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Separate SwiftPM builds also work with Command Line Tools (no xcodebuild).
BINARIES=()
HELPERS=()
for architecture in x86_64 arm64; do
    bash scripts/swift-local.sh build -c release --arch "$architecture"
    BIN_DIR="$(bash scripts/swift-local.sh build -c release --arch "$architecture" --show-bin-path)"
    BINARIES+=("$BIN_DIR/iMacMonitor")
    HELPERS+=("$BIN_DIR/MacPulseFanHelper")
done
APP_DIR="$PWD/dist/MacPulse.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
bash scripts/build-icon.sh
cp "$PWD/dist/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/iMacMonitor"
lipo -create "${HELPERS[@]}" -output "$APP_DIR/Contents/MacOS/MacPulseFanHelper"
codesign --force --sign - "$APP_DIR/Contents/MacOS/MacPulseFanHelper"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>iMacMonitor</string>
<key>CFBundleIdentifier</key><string>local.iMacMonitor</string>
<key>CFBundleName</key><string>MacPulse</string>
<key>CFBundleDisplayName</key><string>MacPulse</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
