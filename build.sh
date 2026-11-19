#!/bin/bash
# Builds CatChaser.app. Requires Xcode or the Command Line Tools (xcode-select --install).
set -e
cd "$(dirname "$0")"

APP="KittyChasingYourMouse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O KittyChasingYourMouse.swift -o "$APP/Contents/MacOS/KittyChasingYourMouse" -framework Cocoa

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Cat Chaser</string>
  <key>CFBundleIdentifier</key><string>com.aquabrium.kitty_chasing_your_mouse</string>
  <key>CFBundleExecutable</key><string>KittyChasingYourMouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP — launching…"
"./$APP/Contents/MacOS/KittyChasingYourMouse"
