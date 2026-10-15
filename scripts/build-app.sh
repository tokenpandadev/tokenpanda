#!/bin/sh
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# Builds the .app bundle from the release binary: Info.plist with LSUIElement, the hook script and the app icon as resources,
# an ad hoc signature, then a zip with its SHA-256. No Xcode, no network.
#   scripts/build-app.sh [version]
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.2}"
NAME="tokenpanda"
BUNDLE_ID="dev.tokenpanda.app"
BUILD="build"
APP="$BUILD/$NAME.app"

swift build -c release 2>&1 | grep -v "ld: warning: search path" || true
BIN=".build/release/$NAME"
[ -x "$BIN" ] || { echo "release binary missing"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp hook/statusline.sh "$APP/Contents/Resources/hook.sh"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 tokenpanda</string>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
EOF
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=2 "$APP"

ZIP="$BUILD/$NAME-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
( cd "$BUILD" && shasum -a 256 "$(basename "$ZIP")" ) | tee "$ZIP.sha256"
echo "built $APP and $ZIP"
