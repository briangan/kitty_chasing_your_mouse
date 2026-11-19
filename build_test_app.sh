#!/bin/bash
# Builds $APPNAME.app. Requires Xcode or the Command Line Tools (xcode-select --install).
set -e
cd "$(dirname "$0")"

APPNAME="TestCursor"
rm -rf "$APPNAME.app"
mkdir -p "$APPNAME.app/Contents/MacOS"

swiftc -O "$APPNAME.swift" -o "$APPNAME.app/Contents/MacOS/$APPNAME" -framework Cocoa

cat > "$APPNAME.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TestApp</string>
  <key>CFBundleIdentifier</key><string>com.aquabrium.test_app</string>
  <key>CFBundleExecutable</key><string>TestApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APPNAME.app" >/dev/null 2>&1 || true

echo "Built $APPNAME.app — launching…"
"./$APPNAME.app/Contents/MacOS/$APPNAME"
