#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Xcode was not found at $DEVELOPER_DIR." >&2
  echo "Set DEVELOPER_DIR to the selected Xcode developer directory and try again." >&2
  exit 1
fi

"$ROOT/Scripts/bootstrap.sh"

xcodebuild \
  -quiet \
  -project PowerTools.xcodeproj \
  -scheme PowerTools \
  -configuration Debug \
  -derivedDataPath "$ROOT/DerivedData-Local" \
  CONFIGURATION_BUILD_DIR="$ROOT/build" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  build

codesign --verify --deep --strict --verbose=2 "$ROOT/build/PowerTools.app"

echo
echo "Local app ready: $ROOT/build/PowerTools.app"
