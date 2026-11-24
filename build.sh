#!/bin/bash
# Builds "Kitty Chasing Your Mouse.app". Requires Xcode or the Command Line Tools (xcode-select --install).
set -e
cd "$(dirname "$0")"

NAME="Kitty Chasing Your Mouse"
APP="$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library KittyChasingYourMouse.swift KittyController.swift KittyView.swift -o "$APP/Contents/MacOS/KittyChasingYourMouse" -framework Cocoa

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kitty Chasing Your Mouse</string>
  <key>CFBundleDisplayName</key><string>Kitty Chasing Your Mouse</string>
  <key>CFBundleIdentifier</key><string>com.example.kittychasingyourmouse</string>
  <key>CFBundleExecutable</key><string>KittyChasingYourMouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>CFBundleShortVersionString</key><string>0.3</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP — launching…"
open "$APP"