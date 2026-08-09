#!/usr/bin/env python3

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SELF = Path(__file__).resolve()

DISCARDED_NAMES = re.compile(
    r"Power Tools|PowerTools|power-tools|powertools|SuperMacApp|"
    r"AW Mac Kit|AWMacKit|awmackit",
    re.IGNORECASE,
)
MISSPELLED_NAMES = re.compile(r"Potli Ji|Potliji|PotliJI|PotliJi App\b|PotliJi Power Tools")

# Every exception is an exact line in compatibility or migration code. Adding
# an exception requires naming the concrete external identity that still needs it.
ALLOWED_LINES = {
    "PotliJi/App/AppIdentity.swift": {
        'static let bundleIdentifier = "com.abhi.PowerTools"',
        'static let applicationSupportDirectoryName = "PowerTools"',
        'static let linkRouterScheme = "powertools-link"',
        'static let productScheme = "powertools"',
        'static let onboardingVersionKey = "PowerTools.onboardingVersion"',
        'static let promptOriginKey = "PowerTools.LinkRouter.PromptOrigin"',
        'static let activeFocusTargetIDKey = "PowerTools.LinkRouter.ActiveFocusTargetID"',
    },
    "Config/PotliJi-Info.plist": {
        "<string>powertools-link</string>",
        "<string>powertools</string>",
    },
    "Scripts/build-support.sh": {
        '"$app_path/Contents/PlugIns/PowerToolsSafariExtension.appex" \\',
        '"$app_path/Contents/PlugIns/PowerToolsShareExtension.appex"',
        'find "$repository_root" -type d -name PowerTools.app -prune -print0',
        'echo "Legacy PowerTools.app products still exist under the checkout:" >&2',
    },
    "Scripts/clean-development-builds.sh": {
        '"$ROOT"/*/PowerTools.app|"$ROOT"/PowerTools.app) ;;',
        'find "$ROOT" -type d -name PowerTools.app -prune -print0',
    },
    "ARCHITECTURE.md": {
        "At startup, migration runs before either persistence store is created. The supported files from `~/Library/Application Support/PowerTools/` are copied into the canonical directory through temporary files and verified byte-for-byte; the historical directory is never deleted. Existing canonical files always win, while missing canonical files may be filled from historical data. Unsupported or unreadable historical files remain untouched.",
        "Preferences previously scoped to `com.abhi.PowerTools` are copied key-by-key only when their canonical equivalents are absent. This covers onboarding state, picker position, the active Focus target, and the selected settings pane. Migrated `launchAtLogin` settings are reconciled after settings load. Default HTTP/HTTPS ownership is never migrated or seized; the user may need to select PotliJi once after the bundle-identifier change.",
        "New integrations emit `potliji-link://` (or `potliji://` for product-level commands). The `powertools-link://` and `powertools://` schemes remain registered only as compatibility aliases and reach the same command parser.",
    },
    "BUILDING.md": {
        "On first launch, PotliJi copies supported settings and history from `~/Library/Application Support/PowerTools/` when the canonical files are missing. Copies are staged and byte-verified, historical data is never deleted, and an existing PotliJi file is never overwritten by historical data.",
        "The previous preference domain `com.abhi.PowerTools` is consulted for onboarding, picker position, Focus target, and settings-pane state. The migrated launch-at-login setting is reconciled normally after settings load. Because macOS sees the new bundle identifier as a new handler, users may need to choose PotliJi again for HTTP and HTTPS; migration never changes those associations silently.",
        "The extensions hand the selected page/link to the `potliji-link://` command scheme. The `powertools-link://` and `powertools://` forms remain compatibility aliases for previously generated integrations; new integrations must not emit them. A browser may display a one-time external-application confirmation.",
    },
}

SKIPPED_DIRECTORY_NAMES = {".git", ".build", "build"}


def fail(message: str) -> None:
    raise SystemExit(f"Naming validation failed: {message}")


def forbidden_match(value: str):
    return DISCARDED_NAMES.search(value) or MISSPELLED_NAMES.search(value)


violations: list[str] = []
for path in ROOT.rglob("*"):
    relative = path.relative_to(ROOT)
    if any(part in SKIPPED_DIRECTORY_NAMES for part in relative.parts):
        continue
    if path == SELF:
        continue

    path_match = forbidden_match(relative.as_posix())
    if path_match:
        violations.append(
            f"{relative}: discarded or misspelled product name in path: {path_match.group(0)!r}"
        )
    if not path.is_file():
        continue

    try:
        contents = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue

    allowed = ALLOWED_LINES.get(relative.as_posix(), set())
    for line_number, line in enumerate(contents.splitlines(), start=1):
        if forbidden_match(line) and line.strip() not in allowed:
            violations.append(f"{relative}:{line_number}: {line.strip()}")

if violations:
    fail("discarded umbrella naming escaped the compatibility allowlist:\n  " + "\n  ".join(violations))

required_paths = [
    "PotliJi/App/PotliJiApp.swift",
    "PotliJi/App/AppModule.swift",
    "PotliJiTests",
    "BrowserExtensions/LinkRouter/common",
    "Config/PotliJi-Info.plist",
    "Config/PotliJi.entitlements",
]
missing_paths = [path for path in required_paths if not (ROOT / path).exists()]
if missing_paths:
    fail("canonical paths are missing: " + ", ".join(missing_paths))

project_source = (ROOT / "project.yml").read_text(encoding="utf-8")
required_project_fragments = [
    "name: PotliJi",
    "  PotliJi:",
    "  PotliJiTests:",
    "  LinkRouterSafariExtension:",
    "  LinkRouterShareExtension:",
    "PRODUCT_BUNDLE_IDENTIFIER: com.abhi.PotliJi",
    "PRODUCT_BUNDLE_IDENTIFIER: com.abhi.PotliJi.Tests",
    "PRODUCT_BUNDLE_IDENTIFIER: com.abhi.PotliJi.LinkRouter.SafariExtension",
    "PRODUCT_BUNDLE_IDENTIFIER: com.abhi.PotliJi.LinkRouter.ShareExtension",
]
missing_fragments = [fragment for fragment in required_project_fragments if fragment not in project_source]
if missing_fragments:
    fail("project.yml is missing canonical identities: " + ", ".join(missing_fragments))

print("Naming OK: PotliJi is the sole active umbrella identity; legacy exceptions are narrow and explicit.")
