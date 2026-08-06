#!/usr/bin/env python3

import json
import plistlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXPECTED_WEB_EXTENSION_PERMISSIONS = {"activeTab", "contextMenus"}


def fail(message: str) -> None:
    raise SystemExit(f"Permission policy violation: {message}")


def load_json(relative_path: str) -> dict:
    with (ROOT / relative_path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_plist(relative_path: str) -> dict:
    with (ROOT / relative_path).open("rb") as handle:
        return plistlib.load(handle)


manifest_paths = [
    "BrowserExtensions/PowerToolsLinkRouter/manifest.chrome.json",
    "BrowserExtensions/PowerToolsLinkRouter/manifest.firefox.json",
    "Extensions/SafariWebExtension/Resources/manifest.json",
]
for generated in [
    "BrowserExtensions/PowerToolsLinkRouter/dist/chromium/manifest.json",
    "BrowserExtensions/PowerToolsLinkRouter/dist/firefox/manifest.json",
]:
    if (ROOT / generated).exists():
        manifest_paths.append(generated)

for manifest_path in manifest_paths:
    manifest = load_json(manifest_path)
    permissions = set(manifest.get("permissions", []))
    if permissions != EXPECTED_WEB_EXTENSION_PERMISSIONS:
        fail(
            f"{manifest_path} permissions are {sorted(permissions)}; expected "
            f"{sorted(EXPECTED_WEB_EXTENSION_PERMISSIONS)}"
        )
    for broad_key in ("host_permissions", "optional_host_permissions", "content_scripts"):
        if manifest.get(broad_key):
            fail(f"{manifest_path} declares broad website access through {broad_key}")

host_entitlements = load_plist("Config/PowerTools.entitlements")
if host_entitlements:
    fail(f"host entitlements must remain empty, found {sorted(host_entitlements)}")

host_info = load_plist("Config/PowerTools-Info.plist")
for usage_key in ("NSAccessibilityUsageDescription", "NSAppleEventsUsageDescription"):
    if usage_key in host_info:
        fail(f"host Info.plist must not declare {usage_key}")

expected_extension_entitlements = {"com.apple.security.app-sandbox": True}
for entitlement_path in (
    "Config/SafariWebExtension.entitlements",
    "Config/ShareExtension.entitlements",
):
    entitlements = load_plist(entitlement_path)
    if entitlements != expected_extension_entitlements:
        fail(
            f"{entitlement_path} must contain only the app sandbox entitlement; "
            f"found {entitlements}"
        )

for source_path in (ROOT / "PowerTools").rglob("*.swift"):
    source = source_path.read_text(encoding="utf-8")
    for forbidden in ("/usr/bin/osascript", "NSAppleScript", "AXIsProcessTrusted"):
        if forbidden in source:
            fail(f"{source_path.relative_to(ROOT)} contains privileged automation token {forbidden}")

settings_source = (ROOT / "PowerTools/App/AppSettings.swift").read_text(encoding="utf-8")
for pattern, description in (
    (r"var\s+launchAtLogin\s*=\s*true", "launch at login must default on"),
    (r"var\s+cleanCopiedLinks\s*=\s*false", "automatic clipboard cleaning must default off"),
):
    if re.search(pattern, settings_source) is None:
        fail(description)

catalog_source = (ROOT / "PowerTools/Infrastructure/BrowserCatalog.swift").read_text(encoding="utf-8")
if "contentsOfDirectory" in catalog_source or "applicationRoots" in catalog_source:
    fail("browser discovery must use registered URL handlers instead of sweeping application directories")

print("Permission policy OK")
