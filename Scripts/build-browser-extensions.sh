#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/BrowserExtensions/PowerToolsLinkRouter"

build_one() {
  local browser="$1"
  local manifest="$2"
  local destination="$SOURCE/dist/$browser"
  rm -rf "$destination"
  mkdir -p "$destination"
  cp "$SOURCE/common/"* "$destination/"
  cp "$SOURCE/$manifest" "$destination/manifest.json"
}

build_one chromium manifest.chrome.json
build_one firefox manifest.firefox.json

echo "Built browser extensions in $SOURCE/dist"
