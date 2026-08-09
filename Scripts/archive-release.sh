#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"

# Regenerate the project and every browser-extension distribution before an
# archive. An existing generated project must never make release inputs stale.
"$ROOT/Scripts/bootstrap.sh"

xcodebuild \
  -project PowerTools.xcodeproj \
  -scheme PowerTools \
  -configuration Release \
  -archivePath "$ROOT/build/PowerTools.xcarchive" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  archive

"$ROOT/Scripts/package-browser-extensions.sh"

echo "Archive created at $ROOT/build/PowerTools.xcarchive"
echo "Browser-extension upload packages created under $ROOT/build/browser-extensions"
