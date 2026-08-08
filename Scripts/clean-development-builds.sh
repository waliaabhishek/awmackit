#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/build-support.sh"

while IFS= read -r -d '' directory; do
  case "$directory" in
    "$ROOT"/DerivedData*) ;;
    *)
      echo "Refusing to remove unexpected path: $directory" >&2
      exit 64
      ;;
  esac

  [[ -e "$directory" ]] || continue
  echo "Removing legacy build output: $directory"
  powertools_unregister_apps_under "$directory"
  rm -rf -- "$directory"
done < <(
  find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name 'DerivedData*' -print0
)

powertools_assert_canonical_repo_app "$ROOT"

if [[ -d "$ROOT/build/PowerTools.app" ]]; then
  powertools_register_canonical_app "$ROOT/build/PowerTools.app"
fi

echo "Legacy developer build outputs are clean."
