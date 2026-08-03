#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/build-browser-extensions.sh"

if ! command -v xcodegen >/dev/null 2>&1; then
  cat >&2 <<'MESSAGE'
XcodeGen is required to create PowerTools.xcodeproj.
Install it with Homebrew:

  brew install xcodegen

Then rerun ./Scripts/bootstrap.sh.
MESSAGE
  exit 1
fi

xcodegen generate --spec project.yml

echo
echo "Generated $ROOT/PowerTools.xcodeproj"
echo "Open it in Xcode, select your Development Team for all three targets, and run the PowerTools scheme."
