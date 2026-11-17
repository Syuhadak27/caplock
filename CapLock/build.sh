#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/CapLock.app"
BIN="$APP/Contents/MacOS/CapLock"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target x86_64-apple-macosx13.0 \
  "$ROOT/Sources/main.swift" -o "$BIN"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>id</string>
    <key>CFBundleExecutable</key><string>CapLock</string>
    <key>CFBundleIdentifier</key><string>local.caplock.indicator</string>
    <key>CFBundleName</key><string>CapLock</string>
    <key>CFBundleDisplayName</key><string>CapLock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>CapLock — indikator Caps Lock untuk macOS Ventura+</string>
</dict>
</plist>
EOF

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so the app launches cleanly from a local build.
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Built: $APP"
