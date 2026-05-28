#!/usr/bin/env bash
# 构建摸鱼书摊.app（universal binary，arm64 + x86_64），然后封装到 DMG。
# 用法：./scripts/make_dmg.sh [version]

set -euo pipefail

VERSION="${1:-0.2.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_NAME="摸鱼书摊"

echo "==> 构建 ${APP_NAME}.app（universal，arm64 + x86_64）"

# 共享 SECRET 注入（不入 git）：优先从环境变量 MOYU_SECRET_HEX 读，
# 其次按候选路径找 Reader-Mac-Doc/secret.env。
SECRET="${MOYU_SECRET_HEX:-}"
if [ -z "$SECRET" ]; then
    for f in \
        "$HOME/Desktop/Reader/Reader-Mac-Doc/secret.env" \
        "$HOME/Desktop/Reader-Mac-Doc/secret.env"; do
        if [ -f "$f" ]; then
            SECRET=$(grep -E '^SECRET=' "$f" | head -1 | cut -d= -f2)
            [ -n "$SECRET" ] && break
        fi
    done
fi
if [ -z "$SECRET" ]; then
    echo "⚠️ 没有找到 MOYU_SECRET_HEX，构出的二进制激活会失败"
    EXTRA_CMAKE=""
else
    echo "✓ SECRET 已就位（${#SECRET} hex chars）"
    EXTRA_CMAKE="-DMOYU_SECRET_HEX=$SECRET"
fi

cmake -S "$ROOT/ReaderCore" -B "$BUILD_DIR" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
      $EXTRA_CMAKE >/dev/null
# 默认 target 含 MoyuShutanBundle，构后自动 rename + 资源拷贝
cmake --build "$BUILD_DIR" -j

APP_PATH="$BUILD_DIR/ReaderApp/${APP_NAME}.app"
[ -d "$APP_PATH" ] || { echo "构建失败：未找到 $APP_PATH"; exit 1; }

echo "==> 验证 universal 二进制"
lipo -info "$APP_PATH/Contents/MacOS/ReaderMac"

echo "==> 准备 DMG 暂存目录"
mkdir -p "$DIST_DIR"
STAGE_DIR="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

DMG_PATH="$DIST_DIR/MoyuShutan-$VERSION.dmg"
rm -f "$DMG_PATH"

echo "==> 创建 $DMG_PATH"
hdiutil create -volname "${APP_NAME} $VERSION" \
               -srcfolder "$STAGE_DIR" \
               -ov -format UDZO \
               "$DMG_PATH"

rm -rf "$STAGE_DIR"

echo
echo "==> 完成 — DMG 在："
ls -lh "$DMG_PATH"
echo
echo "SHA256:"
shasum -a 256 "$DMG_PATH"
