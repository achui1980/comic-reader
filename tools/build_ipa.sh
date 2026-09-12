#!/bin/bash
set -e

# ===========================================
# Comic Reader - iOS 未签名 IPA 打包脚本
# 用法: ./tools/build_ipa.sh
#
# 产出一个未签名的 .ipa 文件,可直接用 Sideloadly / AltStore
# 等侧载工具安装(这些工具会在安装时用你的 Apple ID 现场重签名)。
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="Runner"
IPA_NAME="ComicReader"
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
BUILD_DIR="build/ios/iphoneos"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_OUTPUT="$BUILD_DIR/${IPA_NAME}-${VERSION}-unsigned.ipa"

echo "=== Comic Reader IPA Builder (未签名) ==="
echo "Version: $VERSION"
echo ""

# 检查 flutter
if ! command -v flutter &> /dev/null; then
    echo "Error: flutter not found in PATH"
    exit 1
fi

# 清理缓存,避免 Flutter 生成的 ephemeral Swift Package 清单(硬编码 iOS 13.0)
# 与需要更高最低版本的插件(如 flutter-onnxruntime 要求 16.0)冲突
echo "[1/3] Cleaning stale caches (Pods, ephemeral SPM packages)..."
rm -rf ios/Pods ios/Podfile.lock ios/Flutter/ephemeral
flutter pub get > /dev/null
(cd ios && pod install)

# 编译未签名 Release
echo "[2/3] Building iOS release (--no-codesign)..."
flutter build ios --release --no-codesign

# 验证产物
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed - $APP_PATH not found"
    exit 1
fi

echo "[2/3] App built successfully: $APP_PATH"

# 打包成 ipa (Payload/xxx.app 结构)
echo "[3/3] Packaging IPA..."
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -r "$APP_PATH" "$PAYLOAD_DIR/"

rm -f "$IPA_OUTPUT"
# -y: 保留符号链接本身(不展开/跟随),否则会破坏 Flutter.framework 等
# 内部的 Versions/Current 符号链接结构,导致侧载工具报 "Invalid file"
(cd "$BUILD_DIR" && zip -qry "$(basename "$IPA_OUTPUT")" Payload)

rm -rf "$PAYLOAD_DIR"

# 验证 IPA 生成成功
if [ ! -f "$IPA_OUTPUT" ]; then
    echo "Error: IPA creation failed"
    exit 1
fi

IPA_SIZE=$(du -h "$IPA_OUTPUT" | awk '{print $1}')

echo ""
echo "==========================================="
echo "  IPA 打包完成!"
echo "==========================================="
echo ""
echo "  文件: $IPA_OUTPUT"
echo "  大小: $IPA_SIZE"
echo "  版本: $VERSION"
echo ""
echo "=== 安装说明(未签名 ipa,需侧载工具重签) ==="
echo ""
echo "  推荐使用 Sideloadly (https://sideloadly.io):"
echo "  1. 数据线连接设备,信任此电脑"
echo "  2. Sideloadly 中 Apple ID 填邮箱,IPA 选上面的文件,点 Start"
echo "  3. 首次打开需到 设置->通用->VPN与设备管理 信任开发者"
echo ""
echo "  免费 Apple ID 签名 7 天过期,需重新安装续签"
echo "==========================================="
