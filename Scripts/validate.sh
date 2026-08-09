#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/Scripts/build-support.sh"

"$ROOT/Scripts/clean-development-builds.sh"

"$ROOT/Scripts/build-browser-extensions.sh"
python3 "$ROOT/Scripts/validate-browser-extensions.py"
python3 "$ROOT/Scripts/validate-permission-policy.py"
python3 "$ROOT/Scripts/validate-naming.py"

# Exercise the store-upload packager during routine CI so it cannot silently
# rot between release tags. Keep validation artifacts temporary.
(
  BROWSER_PACKAGE_CHECK_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/potliji-browser-package-check.XXXXXX")"
  trap 'rm -rf -- "$BROWSER_PACKAGE_CHECK_ROOT"' EXIT
  OUTPUT_DIR="$BROWSER_PACKAGE_CHECK_ROOT" \
    "$ROOT/Scripts/package-browser-extensions.sh"
)

for json in BrowserExtensions/LinkRouter/dist/*/manifest.json Extensions/SafariWebExtension/Resources/manifest.json; do
  python3 -m json.tool "$json" >/dev/null
  echo "JSON OK: $json"
done

for javascript in BrowserExtensions/LinkRouter/common/*.js BrowserExtensions/LinkRouter/dist/*/*.js; do
  if command -v node >/dev/null 2>&1; then
    node --check "$javascript" >/dev/null
    echo "JavaScript syntax OK: $javascript"
  elif [[ -x /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc ]]; then
    /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc \
      -e 'new Function(readFile(arguments[0]));' -- "$javascript"
    echo "JavaScript syntax OK: $javascript"
  else
    echo "JavaScript syntax validation requires Node.js or JavaScriptCore." >&2
    exit 1
  fi
done

if python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 - <<'PYTHON'
from pathlib import Path
import yaml

with Path("project.yml").open("r", encoding="utf-8") as handle:
    project = yaml.safe_load(handle)

required_targets = {
    "PotliJi",
    "PotliJiTests",
    "LinkRouterSafariExtension",
    "LinkRouterShareExtension",
}
actual_targets = set(project.get("targets", {}))
missing = required_targets - actual_targets
if missing:
    raise SystemExit(f"project.yml is missing targets: {', '.join(sorted(missing))}")
print("YAML OK: project.yml")
PYTHON
else
  ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)' project.yml
  echo "YAML OK: project.yml"
fi

for plist in Config/*.plist Config/*.entitlements; do
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$plist"
  else
    python3 - "$plist" <<'PYTHON'
import plistlib, sys
with open(sys.argv[1], 'rb') as handle:
    plistlib.load(handle)
print(f"PLIST OK: {sys.argv[1]}")
PYTHON
  fi
done

(
  cd Packages/LinkRouterCore
  swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
)

if xcrun --find swift-format >/dev/null 2>&1; then
  xcrun swift-format lint \
    --strict \
    --recursive \
    --configuration .swift-format \
    Packages/LinkRouterCore/Sources \
    Packages/LinkRouterCore/Tests \
    PotliJi \
    PotliJiTests \
    Extensions
else
  echo "Swift format validation skipped (swift-format not installed)."
fi

find PotliJi Extensions -name '*.swift' -print0 | while IFS= read -r -d '' source; do
  swiftc -parse "$source" >/dev/null
  echo "Swift parse OK: $source"
done

bash -n Scripts/*.sh

echo "Source validation completed."

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodegen >/dev/null 2>&1; then
  VALIDATION_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/potliji-validation.XXXXXX")"
  cleanup_validation() {
    potliji_unregister_apps_under "$VALIDATION_ROOT"
    rm -rf -- "$VALIDATION_ROOT"
  }
  trap cleanup_validation EXIT

  xcodegen generate --spec project.yml
  xcodebuild \
    -project PotliJi.xcodeproj \
    -scheme PotliJi \
    -configuration Debug \
    -derivedDataPath "$VALIDATION_ROOT/Debug" \
    CODE_SIGNING_ALLOWED=NO \
    build
  xcodebuild \
    -project PotliJi.xcodeproj \
    -scheme PotliJi \
    -configuration Release \
    -derivedDataPath "$VALIDATION_ROOT/Release" \
    CODE_SIGNING_ALLOWED=NO \
    build
  xcodebuild \
    -project PotliJi.xcodeproj \
    -scheme PotliJi \
    -configuration Debug \
    -derivedDataPath "$VALIDATION_ROOT/Tests" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=YES \
    test
else
  echo "Xcode build skipped: this validation stage requires macOS with Xcode and XcodeGen."
fi

potliji_assert_canonical_repo_app "$ROOT"
