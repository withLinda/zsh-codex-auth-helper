#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-2026.05.12}"
VERSION="${VERSION#v}"
TAG="v$VERSION"

APP_NAME="ZshCodexAuthHelper"
SCHEME="ZshCodexAuthHelper"
PROJECT="ZshCodexAuthHelper.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
RELEASE_PRODUCTS="$DERIVED_DATA/Build/Products/Release"
APP_BUNDLE="$RELEASE_PRODUCTS/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$ROOT_DIR/build/release-dmg-$TAG"
STAGING_DIR="$WORK_DIR/staging"
DMG_NAME="CodexAuthHelper-$TAG.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
VOLUME_NAME="Codex Auth Helper $TAG"

cd "$ROOT_DIR"

echo "Building $APP_NAME $TAG..."
xcodegen generate >/dev/null
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION=1 \
  build

rm -rf "$WORK_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"

echo "Preparing DMG contents..."
/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating $DMG_PATH..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Verifying DMG..."
hdiutil verify "$DMG_PATH"

echo "Writing checksum..."
HASH="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
printf '%s  dist/%s\n' "$HASH" "$DMG_NAME" > "$CHECKSUM_PATH"

echo "Created:"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
