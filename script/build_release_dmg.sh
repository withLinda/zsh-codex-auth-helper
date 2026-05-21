#!/usr/bin/env bash
set -euo pipefail

RELEASE_VERSION="${1:-2026.05.21.3}"
RELEASE_VERSION="${RELEASE_VERSION#v}"
TAG="v$RELEASE_VERSION"

if [[ -z "${APP_VERSION:-}" ]]; then
  if [[ "$RELEASE_VERSION" =~ ^([0-9]+[.][0-9]+[.][0-9]+)([.-].*)?$ ]]; then
    APP_VERSION="${BASH_REMATCH[1]}"
  else
    APP_VERSION="$RELEASE_VERSION"
  fi
fi

if [[ -z "${BUILD_NUMBER:-}" ]]; then
  if [[ "$RELEASE_VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+[.]([0-9]+)$ ]]; then
    BUILD_NUMBER="${BASH_REMATCH[1]}"
  else
    BUILD_NUMBER=1
  fi
fi

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

echo "Building $APP_NAME $APP_VERSION ($BUILD_NUMBER) for release $TAG..."
xcodegen generate >/dev/null
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
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
printf '%s  %s\n' "$HASH" "$DMG_NAME" > "$CHECKSUM_PATH"

echo "Created:"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
