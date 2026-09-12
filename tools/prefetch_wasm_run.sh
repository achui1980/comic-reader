#!/usr/bin/env bash
# 预下载 wasm_run 的预编译动态库到 native_libs/。
#
# 为什么需要这个脚本：
#   wasm_run 的 native assets 构建 hook 默认用 buildMode=fetch，在构建时自己去
#   GitHub Release 拉预编译库。它内部用的是裸 HttpClient()，既不读 HTTPS_PROXY
#   也没有任何重试——一次 TLS 握手抖动就会让整个 flutter build 失败：
#     Building assets for package:wasm_run failed.
#     Unhandled exception: HandshakeException: Connection terminated during handshake
#   所以 pubspec.yaml 把 buildMode 改成了 local，改由本脚本用 curl（走代理 + 重试
#   + sha256 校验）预先把库放到 native_libs/，构建过程本身不再联网。
#
# 用法:
#   ./tools/prefetch_wasm_run.sh                 # 当前主机能构建的所有平台
#   ./tools/prefetch_wasm_run.sh macos android   # 只下指定平台
#   ./tools/prefetch_wasm_run.sh --all           # 全平台
#
# 平台名: macos | ios | android | windows | linux
#
# 注意: 文件名必须正好是 asset 名（wasm_run_dart-dynamic-<rust-target>，无扩展名），
# 这是 wasm_run hook 在 local 模式下查找库的约定，不要重命名。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/native_libs"

# 与 pubspec.lock 里的 wasm_run 版本对应。升级 wasm_run 时必须同步更新此处的
# 版本号和下面的 sha256 表，取值见:
#   ~/.pub-cache/hosted/pub.dev/wasm_run-<ver>/hook/build.dart 的 assetsSha256
WASM_RUN_RELEASE="wasm_run-v0.2.0"
BASE_URL="https://github.com/juancastillo0/wasm_run/releases/download/${WASM_RUN_RELEASE}"
LIBRARY_NAME="wasm_run_dart"
LIBRARY_TYPE="dynamic"

MAX_RETRY=6

# bash 3.2（macOS 自带）没有关联数组，用 case 函数代替。
sha_for_target() {
  case "$1" in
    aarch64-apple-darwin)   echo "1654553b0782eca999cd5ce3ae9610d5f338e27fcb82a5856e0cdf67acf1b2d9" ;;
    x86_64-apple-darwin)    echo "aa7cfd700e79815c3f04485c8ebb723751c02fb97f27eede1d1270ab3f5829db" ;;
    aarch64-apple-ios)      echo "afb7ed40a7b19b496bf568d42121deddf6263cb1b0a52ec067c1aca6edb93145" ;;
    aarch64-apple-ios-sim)  echo "9484c9a60234ffe5cec88d2d438ebfc8a483c6841324273c35aa39e1f6e74e5f" ;;
    x86_64-apple-ios)       echo "c59128e7431dcb0ce0315e358acdb61ab74b8988d593bcc10b324fcc1cd93306" ;;
    aarch64-linux-android)  echo "a81fae4074d0702bc9ff18b8de6b3ea5947ca8c8cef68db976460feae0024506" ;;
    armv7-linux-androideabi) echo "0f72f5e5e5ccb26c92504e79c9be019192be64de885bbbb90ba9d0de11306ede" ;;
    x86_64-linux-android)   echo "5a95b4529715b5ed33e881b5fd4009050025e653f9d01f4c8b5e6a9c6f6e5f19" ;;
    i686-linux-android)     echo "1447b88b9e5fd5d4e95a8218519037152fb1ebd13fbc11673a16cbfd57e500f8" ;;
    x86_64-pc-windows-msvc) echo "e534e344eda090e141a0d22234f7c37fdfa76aad9ea5b4101816cf32f95c61b8" ;;
    aarch64-pc-windows-msvc) echo "9998fd1553f672a5e81c3771290a65e8138e57e997133f8d3c88fbbb8f15ad61" ;;
    x86_64-unknown-linux-gnu) echo "5a0df6b8992c112a66dca94efeacc87a05ac3c695e2ddf38fea8e32dc47ee05f" ;;
    aarch64-unknown-linux-gnu) echo "7b292f2e2ed7edae34de22c8813ac453830e63450b9d1bd2d277f389379964ee" ;;
    armv7-unknown-linux-gnueabihf) echo "c5acb2bacb78a397b10d8f5b5afe8e30705395569a625683888c017a967210ce" ;;
    riscv64gc-unknown-linux-gnu) echo "78255e9397080a62f8cfa55d685c26445845ec071943ffd6033205f7f9c02da9" ;;
    *) echo "" ;;
  esac
}

targets_for_platform() {
  case "$1" in
    macos)   echo "aarch64-apple-darwin x86_64-apple-darwin" ;;
    ios)     echo "aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios" ;;
    android) echo "aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android" ;;
    windows) echo "x86_64-pc-windows-msvc aarch64-pc-windows-msvc" ;;
    linux)   echo "x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu" ;;
    # 注意: 这里只能 return，不能 exit。本函数是在 $( ) 里调用的，
    # exit 只会退出命令替换的子 shell，主流程会拿到空列表继续跑完并「假装成功」。
    *) return 1 ;;
  esac
}

# 主机默认平台：把该主机上 flutter 可能构建的目标一次性备齐。
default_platforms() {
  case "$(uname -s)" in
    Darwin) echo "macos ios android" ;;
    Linux)  echo "linux android" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows android" ;;
    *) echo "macos" ;;
  esac
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# 下载单个 asset：已存在且 sha256 正确则跳过；下载写临时文件后原子移动，
# 避免留下半截文件让后续构建拿到坏库。
fetch_target() {
  local target="$1"
  local expected asset dest url tmp got attempt
  expected="$(sha_for_target "$target")"
  if [ -z "$expected" ]; then
    echo "没有 $target 的 sha256 记录，无法校验，中止。" >&2
    exit 1
  fi
  asset="${LIBRARY_NAME}-${LIBRARY_TYPE}-${target}"
  dest="$OUT_DIR/$asset"
  url="$BASE_URL/$asset"

  if [ -f "$dest" ]; then
    got="$(sha256_of "$dest")"
    if [ "$got" = "$expected" ]; then
      echo "已就位，跳过: $asset"
      return 0
    fi
    echo "$asset 已存在但 sha256 不符（${got}），重新下载。" >&2
    rm -f "$dest"
  fi

  tmp="$dest.part"
  attempt=1
  while [ "$attempt" -le "$MAX_RETRY" ]; do
    rm -f "$tmp"
    echo "下载 $asset （第 $attempt/$MAX_RETRY 次尝试）"
    # curl 会自动读取环境里的 HTTPS_PROXY/https_proxy。
    if curl -fL -sS --connect-timeout 20 --max-time 600 -o "$tmp" "$url"; then
      got="$(sha256_of "$tmp")"
      if [ "$got" = "$expected" ]; then
        mv "$tmp" "$dest"
        echo "校验通过: $asset"
        return 0
      fi
      echo "sha256 校验失败: 期望 $expected 实际 $got" >&2
    fi
    rm -f "$tmp"
    attempt=$((attempt + 1))
    [ "$attempt" -le "$MAX_RETRY" ] && sleep 2
  done

  echo "下载 $asset 失败（已重试 $MAX_RETRY 次）: $url" >&2
  exit 1
}

platforms=""
if [ "$#" -eq 0 ]; then
  platforms="$(default_platforms)"
  echo "未指定平台，按当前主机默认下载: $platforms"
elif [ "$1" = "--all" ]; then
  platforms="macos ios android windows linux"
else
  platforms="$*"
fi

mkdir -p "$OUT_DIR"

for platform in $platforms; do
  if ! targets="$(targets_for_platform "$platform")"; then
    echo "未知平台: ${platform}（可用: macos ios android windows linux）" >&2
    exit 2
  fi
  echo ""
  echo "=== $platform ==="
  for target in $targets; do
    fetch_target "$target"
  done
done

echo ""
echo "全部就位: $OUT_DIR"
echo "（pubspec.yaml 的 hooks.user_defines.wasm_run.localPath 指向 native_libs/）"
