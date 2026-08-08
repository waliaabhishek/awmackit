#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/Scripts/build-support.sh"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Xcode was not found at $DEVELOPER_DIR." >&2
  echo "Set DEVELOPER_DIR to the selected Xcode developer directory and try again." >&2
  exit 1
fi

"$ROOT/Scripts/bootstrap.sh"
"$ROOT/Scripts/clean-development-builds.sh"

BUILD_ROOT="$ROOT/build"
DERIVED_DATA_DIR="$BUILD_ROOT/DerivedData"
APP_PATH="$BUILD_ROOT/PowerTools.app"

mkdir -p "$BUILD_ROOT"

xcodebuild \
  -quiet \
  -project PowerTools.xcodeproj \
  -scheme PowerTools \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CONFIGURATION_BUILD_DIR="$BUILD_ROOT" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  build

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
powertools_register_canonical_app "$APP_PATH"
powertools_assert_canonical_repo_app "$ROOT"

echo
echo "Canonical local app ready: $APP_PATH"
