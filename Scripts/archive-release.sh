#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"

if [[ ! -d PowerTools.xcodeproj ]]; then
  "$ROOT/Scripts/bootstrap.sh"
fi

xcodebuild \
  -project PowerTools.xcodeproj \
  -scheme PowerTools \
  -configuration Release \
  -archivePath "$ROOT/build/PowerTools.xcarchive" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  archive

echo "Archive created at $ROOT/build/PowerTools.xcarchive"
