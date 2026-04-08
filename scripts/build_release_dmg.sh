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
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"

has_matching_signing_identity() {
  local identity_type="$1"
  local team_id="$2"
  local identities

  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  [[ -n "$identities" ]] || return 1

  if [[ -n "$team_id" ]]; then
    printf '%s\n' "$identities" | grep -Eq "\"${identity_type}: .*\\(${team_id}\\)\""
  else
    printf '%s\n' "$identities" | grep -Eq "\"${identity_type}: "
  fi
}

resolve_build_mode() {
  local build_settings code_sign_identity development_team

  if [[ "$FORCE_UNSIGNED_BUILD" == "1" ]]; then
    echo "unsigned"
    return
  fi

  build_settings="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null)"
  code_sign_identity="$(printf '%s\n' "$build_settings" | awk -F' = ' '/CODE_SIGN_IDENTITY = / {print $2; exit}')"
  development_team="$(printf '%s\n' "$build_settings" | awk -F' = ' '/DEVELOPMENT_TEAM = / {print $2; exit}')"

  if [[ -z "$code_sign_identity" || "$code_sign_identity" == "-" ]]; then
    echo "unsigned"
    return
  fi

  if has_matching_signing_identity "$code_sign_identity" "$development_team"; then
    echo "signed"
    return
  fi

  if [[ "$REQUIRE_SIGNING" == "1" ]]; then
    echo "Missing signing identity '${code_sign_identity}' for team '${development_team}'." >&2
    exit 1
  fi

  echo "unsigned"
}

mkdir -p "$DIST_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/dmg"

BUILD_MODE="$(resolve_build_mode)"
BUILD_ARGS=(
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "$DESTINATION" \
  ONLY_ACTIVE_ARCH=NO
)

if [[ "$BUILD_MODE" == "unsigned" ]]; then
  BUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO)
  echo "Building $SCHEME ($CONFIGURATION, unsigned)..."
  echo "Developer ID certificate not available. Falling back to unsigned build."
else
  echo "Building $SCHEME ($CONFIGURATION, signed)..."
fi

xcodebuild \
  "${BUILD_ARGS[@]}" \
  build

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
