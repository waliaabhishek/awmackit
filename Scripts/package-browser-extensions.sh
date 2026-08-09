#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$#" -gt 2 ]]; then
  echo "Usage: $0 [manifest-version] [artifact-version]" >&2
  echo "Example: $0 1.0.0 1.0.0" >&2
  echo "Preview example: $0 1.0.0 1.0.0-preview.1" >&2
  exit 64
fi

EXPECTED_VERSION="${1:-}"
ARTIFACT_VERSION="${2:-}"

for command in python3 zip unzip shasum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Browser-extension packaging requires $command." >&2
    exit 1
  fi
done

"$ROOT/Scripts/build-browser-extensions.sh"
python3 "$ROOT/Scripts/validate-browser-extensions.py"

MANIFEST_VERSION="$(python3 - "$ROOT/BrowserExtensions/LinkRouter/manifest.chrome.json" <<'PYTHON'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["version"])
PYTHON
)"

if [[ -n "$EXPECTED_VERSION" && "$EXPECTED_VERSION" != "$MANIFEST_VERSION" ]]; then
  echo "Expected browser-extension version $EXPECTED_VERSION; manifests contain $MANIFEST_VERSION." >&2
  exit 1
fi

if [[ -z "$ARTIFACT_VERSION" ]]; then
  ARTIFACT_VERSION="$MANIFEST_VERSION"
fi
if [[ ! "$ARTIFACT_VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]]; then
  echo "Artifact version contains unsupported characters: $ARTIFACT_VERSION" >&2
  exit 64
fi

BUILD_ROOT="$ROOT/build"
OUTPUT_DIR="${OUTPUT_DIR:-$BUILD_ROOT/browser-extensions}"
mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/potliji-browser-packages.XXXXXX")"
cleanup() {
  rm -rf -- "$STAGING_ROOT"
}
trap cleanup EXIT

package_one() {
  local browser="$1"
  local display_name="$2"
  local source_directory="$ROOT/BrowserExtensions/LinkRouter/dist/$browser"
  local staging_directory="$STAGING_ROOT/$browser"
  local zip_name="PotliJi-LinkRouter-${display_name}-v${ARTIFACT_VERSION}.zip"
  local temporary_zip="$STAGING_ROOT/$zip_name"
  local file_list="$STAGING_ROOT/$browser.files"
  local entry_list="$STAGING_ROOT/$browser.entries"

  mkdir -p "$staging_directory"
  cp -R "$source_directory/." "$staging_directory/"

  # Fixed timestamps, sorted paths, and stripped ZIP metadata make identical
  # extension inputs produce identical store-upload archives.
  find "$staging_directory" -exec touch -t 202001010000 {} +
  (
    cd "$staging_directory"
    find . -type f -print | LC_ALL=C sort | sed 's#^\./##' > "$file_list"
    COPYFILE_DISABLE=1 zip -X -q "$temporary_zip" -@ < "$file_list"
  )

  unzip -Z1 "$temporary_zip" > "$entry_list"
  if ! grep -Fx 'manifest.json' "$entry_list" >/dev/null; then
    echo "$zip_name does not contain manifest.json at its root." >&2
    exit 1
  fi
  unzip -p "$temporary_zip" manifest.json | python3 -m json.tool >/dev/null

  mv -f "$temporary_zip" "$OUTPUT_DIR/$zip_name"
  (
    cd "$OUTPUT_DIR"
    shasum -a 256 "$zip_name" > "$zip_name.sha256"
  )
  echo "Packaged $OUTPUT_DIR/$zip_name"
}

package_one chromium Chromium
package_one firefox Firefox

echo "Browser-extension upload packages ready at $OUTPUT_DIR"
