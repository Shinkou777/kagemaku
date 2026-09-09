#!/bin/bash
# 编译 src/*.swift，生成图标，组装 Kagemaku.app
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Kagemaku"
APP_DIR="${KAGEMAKU_APP_DIR:-/Applications/$APP_NAME.app}"
BIN="$APP_DIR/Contents/MacOS/$APP_NAME"
BUNDLE_ID="${KAGEMAKU_BUNDLE_ID:-app.shinkolab.kagemaku}"
VERSION="${KAGEMAKU_VERSION:-${GITHUB_REF_NAME:-0.1.0}}"
VERSION="${VERSION#v}"
ARCH="$(uname -m)"
DEPLOY_TARGET="${KAGEMAKU_DEPLOY_TARGET:-14.0}"

echo "[1/4] 编译 ..."
/usr/bin/swiftc -O \
  -target "${ARCH}-apple-macos${DEPLOY_TARGET}" \
  "$REPO"/src/*.swift \
  -o /tmp/kagemaku-bin

echo "[2/4] 生成图标 ..."
/usr/bin/swift "$REPO/tools/make-icon.swift" >/dev/null
iconutil -c icns /tmp/Kagemaku.iconset -o /tmp/Kagemaku.icns

echo "[3/4] 组装 $APP_NAME.app ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp /tmp/kagemaku-bin "$BIN"
cp /tmp/Kagemaku.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                  <string>Kagemaku</string>
    <key>CFBundleDisplayName</key>           <string>影幕</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>        <string>$DEPLOY_TARGET</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
</dict>
</plist>
PLIST

echo "[4/4] 签名 ..."
# ad-hoc 签名，让 TCC（屏幕录制授权）能认住这个 App
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null 2>&1 || true

echo "完成"
echo "  App: $APP_DIR"
echo "  跑起来: open '$APP_DIR'"
