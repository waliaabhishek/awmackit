#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/build-support.sh"

while IFS= read -r -d '' legacy_app; do
  case "$legacy_app" in
    "$ROOT"/*/PowerTools.app|"$ROOT"/PowerTools.app) ;;
    *)
      echo "Refusing to remove unexpected legacy app path: $legacy_app" >&2
      exit 64
      ;;
  esac
  echo "Removing legacy runnable product: $legacy_app"
  potliji_unregister_legacy_app_bundle "$legacy_app"
  rm -rf -- "$legacy_app"
done < <(
  find "$ROOT" -type d -name PowerTools.app -prune -print0
)

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
  potliji_unregister_apps_under "$directory"
  rm -rf -- "$directory"
done < <(
  find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name 'DerivedData*' -print0
)

potliji_assert_canonical_repo_app "$ROOT"

if [[ -d "$ROOT/build/PotliJi.app" ]]; then
  potliji_register_canonical_app "$ROOT/build/PotliJi.app"
fi

echo "Legacy developer build outputs are clean."
