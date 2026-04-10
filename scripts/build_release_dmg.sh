#!/bin/zsh

set -euo pipefail

pause_on_exit() {
  local exit_code=$?
  trap - EXIT

  if [[ -t 0 ]]; then
    echo
    if (( exit_code == 0 )); then
      read -rsk 1 "?Build finished. Press any key to exit..."
    else
      read -rsk 1 "?Build failed with exit code ${exit_code}. Press any key to exit..."
    fi
    echo
  fi

  exit "$exit_code"
}
trap pause_on_exit EXIT

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
DIST_DIR="$ROOT_DIR/dist"
TMP_DIR="$ROOT_DIR/.release-tmp"
SCHEME="MacBackroom"
PROJECT="$ROOT_DIR/MacBackroom.xcodeproj"
CONFIGURATION="Release"
DESTINATION="generic/platform=macOS"
FORCE_UNSIGNED_BUILD="${FORCE_UNSIGNED_BUILD:-0}"

mkdir -p "$DIST_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/dmg"

BUILD_ARGS=(
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "$DESTINATION" \
  ONLY_ACTIVE_ARCH=NO
)

if [[ "$FORCE_UNSIGNED_BUILD" == "1" ]]; then
  BUILD_MODE="unsigned"
  echo "Building $SCHEME ($CONFIGURATION, unsigned)..."
  xcodebuild "${BUILD_ARGS[@]}" CODE_SIGNING_ALLOWED=NO build
else
  BUILD_MODE="signed"
  echo "Building $SCHEME ($CONFIGURATION, local-signed if available)..."
  if ! xcodebuild "${BUILD_ARGS[@]}" build; then
    BUILD_MODE="unsigned"
    echo "Signed build failed. Falling back to unsigned build."
    xcodebuild "${BUILD_ARGS[@]}" CODE_SIGNING_ALLOWED=NO build
  fi
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)"
BUILD_NUMBER="$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion)"
DMG_BASENAME="${SCHEME}-${VERSION}-${BUILD_NUMBER}"
DMG_PATH="$DIST_DIR/${DMG_BASENAME}.dmg"
SHA_PATH="$DIST_DIR/${DMG_BASENAME}.sha256"

rm -f "$DMG_PATH" "$SHA_PATH"
ditto "$APP_PATH" "$DIST_DIR/$SCHEME.app"

ditto "$APP_PATH" "$TMP_DIR/dmg/$SCHEME.app"
ln -s /Applications "$TMP_DIR/dmg/Applications"

echo "Creating DMG..."
hdiutil create \
  -volname "$SCHEME" \
  -srcfolder "$TMP_DIR/dmg" \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$SHA_PATH"

echo "Created:"
echo "  App:    $DIST_DIR/$SCHEME.app"
echo "  DMG:    $DMG_PATH"
echo "  SHA256: $SHA_PATH"
if [[ "$BUILD_MODE" == "unsigned" ]]; then
  echo "  Note:   App bundle is unsigned."
fi
