#!/usr/bin/env bash
# Build Reader-Mac.app as a universal binary, then wrap it in a DMG.
# Usage: ./scripts/make_dmg.sh [version]

set -euo pipefail

VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"

echo "==> Building Reader-Mac.app (universal, arm64 + x86_64)"
cmake -S "$ROOT/ReaderCore" -B "$BUILD_DIR" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" >/dev/null
cmake --build "$BUILD_DIR" --target ReaderMac -j

APP_PATH="$BUILD_DIR/ReaderApp/ReaderMac.app"
[ -d "$APP_PATH" ] || { echo "Build failed: $APP_PATH not found"; exit 1; }

echo "==> Verifying universal binary"
lipo -info "$APP_PATH/Contents/MacOS/ReaderMac"

echo "==> Preparing DMG staging dir"
mkdir -p "$DIST_DIR"
STAGE_DIR="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

DMG_PATH="$DIST_DIR/Reader-Mac-$VERSION.dmg"
rm -f "$DMG_PATH"

echo "==> Creating $DMG_PATH"
hdiutil create -volname "Reader-Mac $VERSION" \
               -srcfolder "$STAGE_DIR" \
               -ov -format UDZO \
               "$DMG_PATH"

rm -rf "$STAGE_DIR"

echo
echo "==> Done. DMG at:"
ls -lh "$DMG_PATH"
echo
echo "SHA256:"
shasum -a 256 "$DMG_PATH"
