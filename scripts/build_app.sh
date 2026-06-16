#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="DrPaste"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SPM_BIN="$ROOT/.build/arm64-apple-macosx/$CONFIG/$APP_NAME"
SPM_BUNDLE="$ROOT/.build/arm64-apple-macosx/$CONFIG/DrPaste_DrPaste.bundle"
VERSION="$(/usr/bin/grep -E 'static let version' "$ROOT/Sources/DrPaste/AppBrand.swift" | /usr/bin/sed -E 's/.*"([^"]+)".*/\1/')"

if [[ -z "$VERSION" ]]; then
  VERSION="0.0.0"
fi

echo "==> Building $APP_NAME ($CONFIG)"
cd "$ROOT"
swift build -c "$CONFIG"

echo "==> Creating $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$SPM_BIN" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

if [[ -d "$SPM_BUNDLE" ]]; then
  cp -R "$SPM_BUNDLE" "$RESOURCES/"
fi

if [[ -f "$ROOT/Sources/DrPaste/Resources/AppIcon.svg" ]]; then
  cp "$ROOT/Sources/DrPaste/Resources/AppIcon.svg" "$RESOURCES/AppIcon.svg"
fi
if [[ -f "$ROOT/Sources/DrPaste/Resources/MenuBarIcon.svg" ]]; then
  cp "$ROOT/Sources/DrPaste/Resources/MenuBarIcon.svg" "$RESOURCES/MenuBarIcon.svg"
fi

ICON_PNG="$ROOT/DrPaste.com.png"
ICONSET="$ROOT/.build/AppIcon.iconset"
if [[ -f "$ICON_PNG" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.ctrl8.drpaste</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>DrPaste uses Apple Events to return focus to the app you were working in before pasting.</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 iLya Os.</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS/PkgInfo"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> Codesigning with $CODESIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
  echo "==> Skipping codesign (set CODESIGN_IDENTITY to sign)"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ZIP="$ROOT/dist/$APP_NAME-$VERSION.zip"
  echo "==> Creating notarization zip"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP"
  echo "==> Submitting to notarytool profile $NOTARY_PROFILE"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"
else
  echo "==> Skipping notarization (set NOTARY_PROFILE to submit)"
fi

DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG" >/dev/null

echo "==> Built:"
echo "    $APP_DIR"
echo "    $DMG"
