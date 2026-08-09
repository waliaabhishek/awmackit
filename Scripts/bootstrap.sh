#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required to validate browser-extension build inputs." >&2
  exit 1
fi

"$ROOT/Scripts/build-browser-extensions.sh"
python3 "$ROOT/Scripts/validate-browser-extensions.py"

if ! command -v xcodegen >/dev/null 2>&1; then
  cat >&2 <<'MESSAGE'
XcodeGen is required to create PotliJi.xcodeproj.
Install it with Homebrew:

  brew install xcodegen

Then rerun ./Scripts/bootstrap.sh.
MESSAGE
  exit 1
fi

xcodegen generate --spec project.yml

echo
echo "Generated $ROOT/PotliJi.xcodeproj"
echo "Open it in Xcode, select your Development Team for all three targets, and run the PotliJi scheme."
