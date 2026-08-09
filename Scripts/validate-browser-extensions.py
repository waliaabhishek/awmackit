#!/usr/bin/env python3

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "BrowserExtensions" / "PowerToolsLinkRouter"
COMMON = SOURCE / "common"
DIST = SOURCE / "dist"

SOURCE_MANIFESTS = {
    "safari": ROOT / "Extensions" / "SafariWebExtension" / "Resources" / "manifest.json",
    "chromium": SOURCE / "manifest.chrome.json",
    "firefox": SOURCE / "manifest.firefox.json",
}

EXTENSION_VERSION = re.compile(r"^(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){0,3}$")
PROJECT_VERSION = re.compile(
    r"^\s*MARKETING_VERSION:\s*[\"']?([0-9]+(?:\.[0-9]+){1,3})[\"']?\s*$",
    re.MULTILINE,
)


def fail(message: str) -> None:
    raise SystemExit(f"Browser-extension validation failed: {message}")


def files_under(directory: Path) -> dict[Path, Path]:
    if not directory.is_dir():
        fail(f"missing directory: {directory.relative_to(ROOT)}")
    return {
        path.relative_to(directory): path
        for path in directory.rglob("*")
        if path.is_file()
    }


common_files = files_under(COMMON)
if not common_files:
    fail("shared source directory is empty")
if Path("manifest.json") in common_files:
    fail("common source must not contain a browser-specific manifest.json")
for relative_path in common_files:
    if any(part.startswith(".") or part == "__MACOSX" for part in relative_path.parts):
        fail(f"shared source contains packaging metadata: {relative_path}")

expected_generated_files = set(common_files) | {Path("manifest.json")}
manifest_versions: dict[str, str] = {}

for browser, source_manifest_path in SOURCE_MANIFESTS.items():
    if not source_manifest_path.is_file():
        fail(f"missing {browser} source manifest: {source_manifest_path.relative_to(ROOT)}")

    with source_manifest_path.open(encoding="utf-8") as handle:
        source_manifest = json.load(handle)

    version = source_manifest.get("version")
    if not isinstance(version, str) or EXTENSION_VERSION.fullmatch(version) is None:
        fail(f"{browser} manifest has invalid extension version: {version!r}")
    manifest_versions[browser] = version

    generated_directory = DIST / browser
    generated_files = files_under(generated_directory)
    actual_generated_files = set(generated_files)
    if actual_generated_files != expected_generated_files:
        missing = sorted(str(path) for path in expected_generated_files - actual_generated_files)
        unexpected = sorted(str(path) for path in actual_generated_files - expected_generated_files)
        fail(
            f"{browser} generated files differ from shared inputs; "
            f"missing={missing}, unexpected={unexpected}"
        )

    for relative_path, source_path in common_files.items():
        if source_path.read_bytes() != generated_files[relative_path].read_bytes():
            fail(f"{browser}/{relative_path} differs from the shared source")

    with generated_files[Path("manifest.json")].open(encoding="utf-8") as handle:
        generated_manifest = json.load(handle)
    if generated_manifest != source_manifest:
        fail(f"{browser}/manifest.json differs from its source manifest")

unique_manifest_versions = set(manifest_versions.values())
if len(unique_manifest_versions) != 1:
    fail(f"browser manifest versions disagree: {manifest_versions}")

extension_version = unique_manifest_versions.pop()
project_source = (ROOT / "project.yml").read_text(encoding="utf-8")
project_versions = set(PROJECT_VERSION.findall(project_source))
if not project_versions:
    fail("project.yml does not declare MARKETING_VERSION")
if project_versions != {extension_version}:
    fail(
        "browser manifest version does not match every project MARKETING_VERSION; "
        f"extension={extension_version}, project={sorted(project_versions)}"
    )

print(
    "Browser extensions OK: "
    f"Safari, Chromium, and Firefox share {len(common_files)} resource files at version "
    f"{extension_version}"
)
