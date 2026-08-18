#!/usr/bin/env bash
# 下载 PoC 所需的 ONNX 模型权重到 native 与 web 两处。
# 用法: ./tools/download_models.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/assets/models"
WEB_DIR="$REPO_ROOT/tools/translation_service/models"

CTD_URL="https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.3/comictextdetector.pt.onnx"
CTD_SHA="1a86ace74961413cbd650002e7bb4dcec4980ffa21b2f19b86933372071d718f"
CTD_NAME="comictextdetector.onnx"

# 气泡检测器（当前 detector）：Manga-Bubble-YOLO (yolo26n)，输入 1280，输出 output0[1,300,6]。
YOLO_URL="https://huggingface.co/Kiuyha/Manga-Bubble-YOLO/resolve/main/onnx/yolo26n.onnx"
YOLO_NAME="comic-bubble-yolo.onnx"

mkdir -p "$NATIVE_DIR" "$WEB_DIR"

download_and_verify() {
  local url="$1" sha="$2" dest="$3"
  if [ -f "$dest" ]; then
    echo "已存在，跳过: $dest"
    return
  fi
  echo "下载 $url -> $dest"
  curl -L --fail -o "$dest" "$url"
  local got
  got="$(shasum -a 256 "$dest" | awk '{print $1}')"
  if [ "$got" != "$sha" ]; then
    echo "sha256 校验失败: 期望 $sha 实际 $got" >&2
    rm -f "$dest"
    exit 1
  fi
  echo "校验通过: $dest"
}

download_no_verify() {
  local url="$1" dest="$2"
  if [ -f "$dest" ]; then
    echo "已存在，跳过: $dest"
    return
  fi
  echo "下载 $url -> $dest"
  curl -L --fail -o "$dest" "$url"
  echo "下载完成: $dest"
}

download_no_verify "$YOLO_URL" "$NATIVE_DIR/$YOLO_NAME"
cp "$NATIVE_DIR/$YOLO_NAME" "$WEB_DIR/$YOLO_NAME"

echo ""
echo "气泡检测器 comic-bubble-yolo 已就位（当前 detector）。"
echo ""
echo "manga-ocr 请手动导出后放到 $NATIVE_DIR/manga-ocr/ 与 $WEB_DIR/manga-ocr/："
echo "  pip install optimum[exporters]"
echo "  optimum-cli export onnx --model kha-white/manga-ocr-base --task vision2seq-lm $NATIVE_DIR/manga-ocr/"
echo "  cp -r $NATIVE_DIR/manga-ocr $WEB_DIR/manga-ocr"
