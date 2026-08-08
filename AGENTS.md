# Power Tools Link Router: Agent Working Agreement

This repository builds a macOS menu-bar application with LaunchServices URL handlers and embedded Safari and Share extensions. Build paths are part of runtime correctness: macOS may discover and register any `PowerTools.app` or extension bundle left in the checkout.

## Repository and project source of truth

- Work from this directory, `PowerTools-LinkRouter`; the parent `SuperMacApp` directory is only a container.
- `project.yml` is the Xcode project source of truth. Do not hand-edit generated `PowerTools.xcodeproj` files.
- Run `./Scripts/bootstrap.sh` after changing `project.yml` or browser-extension sources.
- Use full Xcode through `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Canonical developer build

- `build/PowerTools.app` is the only persistent runnable developer app.
- Build it with `./Scripts/build-local.sh`. The script keeps Xcode intermediates under `build/DerivedData` and registers the canonical app and embedded Safari extension after verification.
- Never launch an app from `DerivedData`, `DerivedData-*`, an `.xcarchive`, a test result, or a temporary validation directory.
- Never create repository-level `DerivedData*` directories. Do not invoke `xcodebuild -derivedDataPath DerivedData...` in this checkout.
- Before rebuilding or runtime testing, quit the running canonical app. After rebuilding, relaunch the exact `build/PowerTools.app` path.
- Run `./Scripts/clean-development-builds.sh` if a legacy `DerivedData*` directory appears. It removes only regenerable repository-level Xcode outputs; it preserves `build/PowerTools.app`.

## Validation builds

- Run the full project validation with `./Scripts/validate.sh`.
- Validation products must be temporary. The validation script builds Debug, Release, and hosted tests under a unique system temporary directory, unregisters generated app/extension bundles, and deletes the directory on exit.
- A successful build is not runtime proof. For system integrations, inspect the exact running executable, external registration state, and perform an end-to-end action.

## Runtime verification

- Confirm the process executable is `build/PowerTools.app/Contents/MacOS/PowerTools`.
- Confirm only `build/PowerTools.app` is a runnable app under the checkout.
- For default-browser work, verify both HTTP and HTTPS handlers resolve to `com.abhi.PowerTools`, then open a real URL and confirm the routing history and destination browser.
- For Safari-extension work, verify the embedded bundle exists at `build/PowerTools.app/Contents/PlugIns/PowerToolsSafariExtension.appex` and inspect PlugInKit/Safari state. Do not infer activation from embedding alone.
- `build-local.sh` uses ad-hoc signing. Safari may hide or reject its embedded extension even with development settings enabled. Full embedded-extension activation requires valid Apple signing; a temporary Safari WebExtension load is only a development fallback.
- Do not use broad Accessibility or screen-recording inspection. If UI geometry must be checked, use narrowly scoped, target-only System Events access and explain why.

## Release boundaries

- Unsigned preview builds are explicitly ad-hoc signed, unnotarized evaluation artifacts. Never describe them as Developer ID signed, notarized, or production-ready.
- Archives and preview packages belong under `build/`; do not launch their nested app copies as developer builds.
- Preserve user changes and keep generated Xcode/DerivedData/build outputs out of commits.
