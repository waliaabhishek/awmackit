# PotliJi: Agent Working Agreement

This repository builds a macOS menu-bar application with LaunchServices URL handlers and embedded Safari and Share extensions. Build paths are part of runtime correctness: macOS may discover and register any `PotliJi.app` or extension bundle left in the checkout.

## Repository and project source of truth

- Work from the repository root. The canonical checkout name is `potliji`.
- `project.yml` is the Xcode project source of truth. Do not hand-edit generated `PotliJi.xcodeproj` files.
- Run `./Scripts/bootstrap.sh` after changing `project.yml` or browser-extension sources.
- Use full Xcode through `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Canonical naming hierarchy

- `PotliJi` is the only product, application, host, and umbrella name.
- `Link Router` is the current module. Its owned types and extensions use names such as `LinkRouterModule`, `LinkRouterSettings`, `LinkRouterSafariExtension`, and `LinkRouterShareExtension`.
- `File Router` is reserved for a future module and must not be added as a placeholder.
- Shared host contracts use neutral names such as `AppModule`, `ModuleRegistry`, and `AppEnvironment`.
- Do not create another product or architectural layer above or beside PotliJi. Run `./Scripts/validate-naming.py` when changing names; its historical-identity allowlist must stay exact and migration-specific.

## Browser-extension source and artifacts

- `BrowserExtensions/LinkRouter/common` is the single source of truth for Safari, Chromium, and Firefox WebExtension HTML/JavaScript.
- Browser-specific manifests remain reviewable source files. Do not duplicate shared WebExtension files under the Safari target or edit generated files under `BrowserExtensions/LinkRouter/dist`.
- `./Scripts/build-browser-extensions.sh` recreates developer-loadable Safari, Chromium, and Firefox folders. `bootstrap.sh`, `build-local.sh`, `validate.sh`, preview packaging, and signed archives invoke it for you.
- Keep every browser manifest version aligned with `MARKETING_VERSION`. `./Scripts/validate-browser-extensions.py` enforces source/output equality and version consistency.
- Use `./Scripts/package-browser-extensions.sh` for deterministic Chromium and Firefox store-upload ZIPs. These ZIPs are unsigned inputs to browser-store review, not published or signed extensions.

## Canonical developer build

- `build/PotliJi.app` is the only persistent runnable developer app.
- Build it with `./Scripts/build-local.sh`. The script keeps Xcode intermediates under `build/DerivedData` and registers the canonical app and embedded Safari extension after verification.
- Never launch an app from `DerivedData`, `DerivedData-*`, an `.xcarchive`, a test result, or a temporary validation directory.
- Never create repository-level `DerivedData*` directories. Do not invoke `xcodebuild -derivedDataPath DerivedData...` in this checkout.
- Before rebuilding or runtime testing, quit the running canonical app. After rebuilding, relaunch the exact `build/PotliJi.app` path.
- Run `./Scripts/clean-development-builds.sh` if a legacy `DerivedData*` directory or retired runnable product appears. It removes only regenerable build outputs and preserves `build/PotliJi.app`.

## Validation builds

- Run the full project validation with `./Scripts/validate.sh`.
- Validation products must be temporary. The validation script builds Debug, Release, and hosted tests under a unique system temporary directory, unregisters generated app/extension bundles, and deletes the directory on exit.
- A successful build is not runtime proof. For system integrations, inspect the exact running executable, external registration state, and perform an end-to-end action.

## Runtime verification

- Confirm the process executable is `build/PotliJi.app/Contents/MacOS/PotliJi`.
- Confirm only `build/PotliJi.app` is a runnable app under the checkout.
- For default-browser work, verify both HTTP and HTTPS handlers resolve to `com.abhi.PotliJi`, then open a real URL and confirm the routing history and destination browser.
- For Safari-extension work, verify the embedded bundle exists at `build/PotliJi.app/Contents/PlugIns/LinkRouterSafariExtension.appex` and inspect PlugInKit/Safari state. Do not infer activation from embedding alone.
- `build-local.sh` uses ad-hoc signing. Safari may hide or reject its embedded extension even with development settings enabled. Full embedded-extension activation requires valid Apple signing; a temporary Safari WebExtension load is only a development fallback.
- Do not use broad Accessibility or screen-recording inspection. If UI geometry must be checked, use narrowly scoped, target-only System Events access and explain why.

## Release boundaries

- Unsigned preview builds are explicitly ad-hoc signed, unnotarized evaluation artifacts. Never describe them as Developer ID signed, notarized, or production-ready.
- Archives and preview packages belong under `build/`; do not launch their nested app copies as developer builds.
- Signed archives must regenerate browser extensions even when `PotliJi.xcodeproj` already exists.
- Preserve user changes and keep generated Xcode/DerivedData/build outputs out of commits.
