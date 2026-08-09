#!/usr/bin/env bash

# Shared registration helpers for build scripts. Keep persistent developer
# products under build/ and make temporary Xcode products invisible to
# LaunchServices and PlugInKit as soon as their job finishes.

LSREGISTER_PATH="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

potliji_unregister_app_bundle() {
  local app_path="$1"
  local plugin_path

  [[ -n "$app_path" && "$app_path" != "/" ]] || return 64

  for plugin_path in \
    "$app_path/Contents/PlugIns/LinkRouterSafariExtension.appex" \
    "$app_path/Contents/PlugIns/LinkRouterShareExtension.appex"
  do
    if [[ -d "$plugin_path" ]] && command -v pluginkit >/dev/null 2>&1; then
      pluginkit -r "$plugin_path" >/dev/null 2>&1 || true
    fi
  done

  if [[ -d "$app_path" && -x "$LSREGISTER_PATH" ]]; then
    "$LSREGISTER_PATH" -u "$app_path" >/dev/null 2>&1 || true
  fi
}

potliji_unregister_legacy_app_bundle() {
  local app_path="$1"
  local plugin_path

  [[ -n "$app_path" && "$app_path" != "/" ]] || return 64

  for plugin_path in \
    "$app_path/Contents/PlugIns/PowerToolsSafariExtension.appex" \
    "$app_path/Contents/PlugIns/PowerToolsShareExtension.appex"
  do
    if [[ -d "$plugin_path" ]] && command -v pluginkit >/dev/null 2>&1; then
      pluginkit -r "$plugin_path" >/dev/null 2>&1 || true
    fi
  done

  if [[ -d "$app_path" && -x "$LSREGISTER_PATH" ]]; then
    "$LSREGISTER_PATH" -u "$app_path" >/dev/null 2>&1 || true
  fi
}

potliji_unregister_apps_under() {
  local search_root="$1"
  local app_path

  [[ -d "$search_root" ]] || return 0

  while IFS= read -r -d '' app_path; do
    potliji_unregister_app_bundle "$app_path"
  done < <(find "$search_root" -type d -name PotliJi.app -prune -print0)
}

potliji_register_canonical_app() {
  local app_path="$1"
  local safari_extension="$app_path/Contents/PlugIns/LinkRouterSafariExtension.appex"

  [[ -d "$app_path" ]] || {
    echo "Cannot register missing app: $app_path" >&2
    return 1
  }

  if [[ -x "$LSREGISTER_PATH" ]]; then
    "$LSREGISTER_PATH" -f "$app_path"
  fi
  if [[ -d "$safari_extension" ]] && command -v pluginkit >/dev/null 2>&1; then
    pluginkit -a "$safari_extension"
  fi
}

potliji_assert_canonical_repo_app() {
  local repository_root="$1"
  local canonical_app="$repository_root/build/PotliJi.app"
  local app_path
  local legacy_app
  local unexpected=()
  local legacy_apps=()

  while IFS= read -r -d '' app_path; do
    if [[ "$app_path" != "$canonical_app" ]]; then
      unexpected+=("$app_path")
    fi
  done < <(
    find "$repository_root" \
      -type d \( -name .git -o -name .build -o -name '*.xcarchive' \) -prune -o \
      -type d -name PotliJi.app -print0
  )

  if (( ${#unexpected[@]} > 0 )); then
    echo "Unexpected PotliJi.app build products exist outside build/PotliJi.app:" >&2
    printf '  %s\n' "${unexpected[@]}" >&2
    return 1
  fi

  while IFS= read -r -d '' legacy_app; do
    legacy_apps+=("$legacy_app")
  done < <(
    find "$repository_root" -type d -name PowerTools.app -prune -print0
  )

  if (( ${#legacy_apps[@]} > 0 )); then
    echo "Legacy PowerTools.app products still exist under the checkout:" >&2
    printf '  %s\n' "${legacy_apps[@]}" >&2
    return 1
  fi
}
