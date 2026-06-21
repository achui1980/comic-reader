#!/bin/bash
set -e

# ===========================================
# Comic Reader - macOS DMG 打包脚本
# 用法: ./tools/build_dmg.sh
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="comic_reader"
DMG_NAME="ComicReader"
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
BUILD_DIR="build/macos/Build/Products/Release"
OUTPUT_DIR="build/dmg"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
ICON_SOURCE="macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"

echo "=== Comic Reader DMG Builder ==="
echo "Version: $VERSION"
echo ""

# 检查 create-dmg
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg not found"
    echo "Install: brew install create-dmg"
    exit 1
fi

# 检查 flutter
if ! command -v flutter &> /dev/null; then
    echo "Error: flutter not found in PATH"
    exit 1
fi

# 编译 Release
echo "[1/4] Building macOS release..."
flutter build macos --release

# 验证产物
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed - $APP_PATH not found"
    exit 1
fi

echo "[2/4] App built successfully: $APP_PATH"

# 生成 .icns 图标用于 DMG 卷图标
ICNS_PATH="/tmp/comic_reader_vol.icns"
echo "[3/4] Generating volume icon..."
mkdir -p /tmp/comic_reader_icon.iconset
sips -z 16 16     "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_16x16.png    > /dev/null 2>&1
sips -z 32 32     "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_16x16@2x.png > /dev/null 2>&1
sips -z 32 32     "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_32x32.png    > /dev/null 2>&1
sips -z 64 64     "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_32x32@2x.png > /dev/null 2>&1
sips -z 128 128   "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_128x128.png  > /dev/null 2>&1
sips -z 256 256   "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_128x128@2x.png > /dev/null 2>&1
sips -z 256 256   "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_256x256.png  > /dev/null 2>&1
sips -z 512 512   "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_256x256@2x.png > /dev/null 2>&1
sips -z 512 512   "$ICON_SOURCE" --out /tmp/comic_reader_icon.iconset/icon_512x512.png  > /dev/null 2>&1
cp "$ICON_SOURCE"              /tmp/comic_reader_icon.iconset/icon_512x512@2x.png
iconutil -c icns /tmp/comic_reader_icon.iconset -o "$ICNS_PATH"
rm -rf /tmp/comic_reader_icon.iconset

# 清理旧 DMG
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

DMG_OUTPUT="$OUTPUT_DIR/${DMG_NAME}-${VERSION}.dmg"

# 生成 DMG
echo "[4/4] Creating DMG..."
create-dmg \
  --volname "$DMG_NAME" \
  --volicon "$ICNS_PATH" \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 150 200 \
  --app-drop-link 450 200 \
  --no-internet-enable \
  "$DMG_OUTPUT" \
  "$APP_PATH" \
  || true  # create-dmg 返回非0但DMG已生成时不要退出

# 验证 DMG 生成成功
if [ ! -f "$DMG_OUTPUT" ]; then
    echo "Error: DMG creation failed"
    exit 1
fi

# 清理临时文件
rm -f "$ICNS_PATH"

DMG_SIZE=$(du -h "$DMG_OUTPUT" | awk '{print $1}')

echo ""
echo "==========================================="
echo "  DMG 打包完成!"
echo "==========================================="
echo ""
echo "  文件: $DMG_OUTPUT"
echo "  大小: $DMG_SIZE"
echo "  版本: $VERSION"
echo ""
echo "=== 分发给用户的安装说明 ==="
echo ""
echo "  1. 双击 DMG 文件打开"
echo "  2. 将 comic_reader 拖到 Applications 文件夹"
echo "  3. 首次打开方法 (重要!):"
echo "     右键点击 app -> 打开 -> 弹出警告点\"打开\""
echo "     或终端执行: xattr -cr /Applications/${APP_NAME}.app"
echo ""
echo "  要求: macOS 11.0 (Big Sur) 或更高版本"
echo "==========================================="
