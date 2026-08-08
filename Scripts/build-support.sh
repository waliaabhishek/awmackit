#!/usr/bin/env bash

# Shared registration helpers for build scripts. Keep persistent developer
# products under build/ and make temporary Xcode products invisible to
# LaunchServices and PlugInKit as soon as their job finishes.

POWERTOOLS_LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

powertools_unregister_app_bundle() {
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

  if [[ -d "$app_path" && -x "$POWERTOOLS_LSREGISTER" ]]; then
    "$POWERTOOLS_LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  fi
}

powertools_unregister_apps_under() {
  local search_root="$1"
  local app_path

  [[ -d "$search_root" ]] || return 0

  while IFS= read -r -d '' app_path; do
    powertools_unregister_app_bundle "$app_path"
  done < <(find "$search_root" -type d -name PowerTools.app -prune -print0)
}

powertools_register_canonical_app() {
  local app_path="$1"
  local safari_extension="$app_path/Contents/PlugIns/PowerToolsSafariExtension.appex"

  [[ -d "$app_path" ]] || {
    echo "Cannot register missing app: $app_path" >&2
    return 1
  }

  if [[ -x "$POWERTOOLS_LSREGISTER" ]]; then
    "$POWERTOOLS_LSREGISTER" -f "$app_path"
  fi
  if [[ -d "$safari_extension" ]] && command -v pluginkit >/dev/null 2>&1; then
    pluginkit -a "$safari_extension"
  fi
}

powertools_assert_canonical_repo_app() {
  local repository_root="$1"
  local canonical_app="$repository_root/build/PowerTools.app"
  local app_path
  local unexpected=()

  while IFS= read -r -d '' app_path; do
    if [[ "$app_path" != "$canonical_app" ]]; then
      unexpected+=("$app_path")
    fi
  done < <(
    find "$repository_root" \
      -type d \( -name .git -o -name .build -o -name '*.xcarchive' \) -prune -o \
      -type d -name PowerTools.app -print0
  )

  if (( ${#unexpected[@]} > 0 )); then
    echo "Unexpected PowerTools.app build products exist outside build/PowerTools.app:" >&2
    printf '  %s\n' "${unexpected[@]}" >&2
    return 1
  fi
}
