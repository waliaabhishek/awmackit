#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/BrowserExtensions/LinkRouter"
COMMON="$SOURCE/common"
DIST="$SOURCE/dist"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/potliji-browser-extensions.XXXXXX")"

cleanup() {
  rm -rf -- "$STAGING_ROOT"
}
trap cleanup EXIT

build_one() {
  local browser="$1"
  local manifest="$2"
  local staging="$STAGING_ROOT/$browser"

  if [[ ! -f "$manifest" ]]; then
    echo "Missing $browser manifest: $manifest" >&2
    exit 1
  fi

  mkdir -p "$staging"
  cp -R "$COMMON/." "$staging/"
  cp "$manifest" "$staging/manifest.json"
}

publish_one() {
  local browser="$1"
  local staging="$STAGING_ROOT/$browser"
  local destination="$DIST/$browser"

  rm -rf -- "$destination"
  mkdir -p "$DIST"
  mv "$staging" "$destination"
}

if [[ ! -d "$COMMON" ]]; then
  echo "Missing shared WebExtension source directory: $COMMON" >&2
  exit 1
fi
if [[ -z "$(find "$COMMON" -type f -print -quit)" ]]; then
  echo "Shared WebExtension source directory is empty: $COMMON" >&2
  exit 1
fi

# Stage every browser before replacing any generated output. A missing source
# file therefore leaves the previously generated distributions untouched.
build_one safari "$ROOT/Extensions/SafariWebExtension/Resources/manifest.json"
build_one chromium "$SOURCE/manifest.chrome.json"
build_one firefox "$SOURCE/manifest.firefox.json"

publish_one safari
publish_one chromium
publish_one firefox

echo "Built Safari, Chromium, and Firefox extensions in $DIST"
