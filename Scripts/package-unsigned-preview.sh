#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/Scripts/build-support.sh"

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <version> <build-number>" >&2
  echo "Example: $0 0.1.0-preview.1 42" >&2
  exit 64
fi

VERSION="$1"
BUILD_NUMBER="$2"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$ ]]; then
  echo "Version must look like 0.1.0-preview.1; received: $VERSION" >&2
  exit 64
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Build number must be a positive integer; received: $BUILD_NUMBER" >&2
  exit 64
fi

# Apple requires CFBundleShortVersionString to contain exactly three numeric
# components. Keep the preview sequence in the tag and artifact name while the
# bundle uses the stable numeric portion.
BUNDLE_VERSION="${VERSION%%-preview.*}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Xcode was not found at $DEVELOPER_DIR." >&2
  exit 1
fi

BUILD_ROOT="$ROOT/build"
OUTPUT_DIR="${OUTPUT_DIR:-$BUILD_ROOT/releases}"
mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"

WORK_DIR="$(mktemp -d "$BUILD_ROOT/unsigned-preview.XXXXXX")"
cleanup() {
  potliji_unregister_apps_under "$WORK_DIR"
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

DERIVED_DATA_DIR="$WORK_DIR/DerivedData"
PRODUCTS_DIR="$WORK_DIR/Products"
APP_PATH="$PRODUCTS_DIR/PotliJi.app"

"$ROOT/Scripts/bootstrap.sh"

# Fail before the expensive universal app build if the release tag's numeric
# version disagrees with the browser manifests or project version.
OUTPUT_DIR="$OUTPUT_DIR" \
  "$ROOT/Scripts/package-browser-extensions.sh" "$BUNDLE_VERSION" "$VERSION"

xcodebuild \
  -quiet \
  -project PotliJi.xcodeproj \
  -scheme PotliJi \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CONFIGURATION_BUILD_DIR="$PRODUCTS_DIR" \
  MARKETING_VERSION="$BUNDLE_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  "ARCHS=arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app was not produced at $APP_PATH." >&2
  exit 1
fi

bundles=(
  "$APP_PATH"
  "$APP_PATH/Contents/PlugIns/LinkRouterSafariExtension.appex"
  "$APP_PATH/Contents/PlugIns/LinkRouterShareExtension.appex"
)

for bundle in "${bundles[@]}"; do
  info_plist="$bundle/Contents/Info.plist"
  if [[ ! -f "$info_plist" ]]; then
    echo "Missing bundle metadata: $info_plist" >&2
    exit 1
  fi

  actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  if [[ "$actual_version" != "$BUNDLE_VERSION" || "$actual_build" != "$BUILD_NUMBER" ]]; then
    echo "Unexpected version in $info_plist: $actual_version ($actual_build)" >&2
    exit 1
  fi

  codesign --verify --strict --verbose=2 "$bundle"
  signing_info="$(codesign -dv --verbose=4 "$bundle" 2>&1)"
  if ! grep -q '^Signature=adhoc$' <<<"$signing_info"; then
    echo "Expected an ad-hoc signature on $bundle." >&2
    exit 1
  fi
  if ! grep -q '^TeamIdentifier=not set$' <<<"$signing_info"; then
    echo "Unexpected signing team on unsigned preview bundle: $bundle" >&2
    exit 1
  fi
done

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

executables=(
  "$APP_PATH/Contents/MacOS/PotliJi"
  "$APP_PATH/Contents/PlugIns/LinkRouterSafariExtension.appex/Contents/MacOS/LinkRouterSafariExtension"
  "$APP_PATH/Contents/PlugIns/LinkRouterShareExtension.appex/Contents/MacOS/LinkRouterShareExtension"
)

for executable in "${executables[@]}"; do
  if [[ ! -x "$executable" ]]; then
    echo "Missing executable: $executable" >&2
    exit 1
  fi

  architectures="$(lipo -archs "$executable")"
  if [[ " $architectures " != *" arm64 "* || " $architectures " != *" x86_64 "* ]]; then
    echo "Expected arm64 and x86_64 in $executable; found: $architectures" >&2
    exit 1
  fi
done

ARTIFACT_BASE="PotliJi-v${VERSION}-macos-universal-unsigned-preview"
ZIP_NAME="$ARTIFACT_BASE.zip"
TEMP_ZIP="$WORK_DIR/$ZIP_NAME"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$TEMP_ZIP"

VERIFY_DIR="$WORK_DIR/verify"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$TEMP_ZIP" "$VERIFY_DIR"
codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/PotliJi.app"

mv -f "$TEMP_ZIP" "$OUTPUT_DIR/$ZIP_NAME"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
)

echo
echo "Unsigned preview ready: $OUTPUT_DIR/$ZIP_NAME"
echo "Checksum ready: $OUTPUT_DIR/$ZIP_NAME.sha256"
echo "Chromium and Firefox preview packages ready in: $OUTPUT_DIR"
