# Building and Running

## 1. Prerequisites

Use a Mac with:

- macOS 14 or later.
- Xcode 16 or later selected with `xcode-select`.
- Homebrew and XcodeGen 2.40 or later.
- An Apple Developer identity when testing embedded extensions or producing a signed archive.

Install XcodeGen:

```bash
brew install xcodegen
```

## 2. Generate the Xcode project

From the repository root:

```bash
./Scripts/bootstrap.sh
```

This builds browser-extension distributions and generates `PowerTools.xcodeproj` from `project.yml`.

The generated project is intentionally not committed. `project.yml` is the source of truth.

## 3. Configure signing

Open `PowerTools.xcodeproj`, then select the same Apple Development Team for all three targets:

- `PowerTools`
- `PowerToolsSafariExtension`
- `PowerToolsShareExtension`

The sample identifiers are:

```text
com.abhi.PowerTools
com.abhi.PowerTools.LinkRouter.SafariExtension
com.abhi.PowerTools.LinkRouter.ShareExtension
```

Change them in `project.yml` when necessary, then regenerate the project. Keep the Safari extension identifier in `ExtensionsSettingsView.swift` synchronized with the target bundle identifier.

## 4. Run the host application

Run the `PowerTools` scheme. The application is an accessory/menu-bar process and does not show a Dock icon.

On first launch it opens Settings. Choose a primary browser or leave **Ask Every Time** as the primary target, then select **Make Default**.

For a local test build that does not require an Apple Developer team, run:

```bash
./Scripts/build-local.sh
open build/PowerTools.app
```

`build/PowerTools.app` is the sole persistent developer app. Xcode intermediates
live under `build/DerivedData`; Debug, Release, test, or analysis products must
not be left in repository-level `DerivedData*` directories because macOS can
discover their duplicate app and extension bundle identifiers. Run
`./Scripts/clean-development-builds.sh` to unregister and remove legacy outputs.

The local build is ad-hoc signed and runs the host application on the current
Mac. Embedding the extensions does not prove Safari will expose or activate
them. Normal embedded-extension activation requires Apple Development signing
for local development or the appropriate distribution signing for releases.

macOS may require explicit confirmation before changing the default browser. Confirm that both HTTP and HTTPS links are assigned to Power Tools in System Settings.

## 5. Test browser-originated links

A default-browser router receives links opened by other applications. Browsers normally consume their own clicked links, so browser-originated routing uses an extension.

### Safari

1. Build all three targets with the same Apple Development Team and run the host app once.
2. Open Safari → Settings → Extensions.
3. Enable **Power Tools Link Router**.
4. Use the toolbar action or link context menu.

For unsigned development only, Safari's Developer settings can load
`Extensions/SafariWebExtension/Resources` as a temporary extension. This is a
short-lived test path, not evidence that the embedded extension is correctly
signed or distributable.

### Chromium-family browsers

The bootstrap script creates:

```text
BrowserExtensions/PowerToolsLinkRouter/dist/chromium
```

Open the browser extension-management page, enable developer mode, and load that folder as an unpacked extension. The toolbar command follows the host app’s **Browser extension always opens the picker** preference; the extension also exposes an explicit picker context-menu/keyboard command.

### Firefox

The bootstrap script creates:

```text
BrowserExtensions/PowerToolsLinkRouter/dist/firefox
```

Load `manifest.json` as a temporary extension through Firefox's debugging interface during development. The toolbar command follows the host app’s picker preference, while the explicit picker action always shows the chooser. Store publication and signing are separate release tasks.

The extensions hand the selected page/link to the `powertools-link://` command scheme. A browser may display a one-time external-application confirmation.

## 6. Test Share, Services, Shortcuts, Focus, and Handoff

### Share extension

Enable the extension under macOS Login Items & Extensions when it does not appear automatically. Share a URL or selected text and choose **Power Tools Link Router**.

### Services

Select text containing one or more URLs, open the Services submenu, and use either:

- **Open URLs with Power Tools**
- **Open URLs with Power Tools Picker**

Services may need to be enabled in Keyboard Shortcuts → Services.

### Shortcuts and App Intents

After launching the signed app, open Shortcuts and search for Power Tools. Included intents cover routing a URL, cleaning a URL, opening clipboard URLs, and changing the primary browser.

### Focus Filter

Add the Power Tools browser filter from a Focus configuration in System Settings. A current macOS 26.5 system regression has been reported in which `SetFocusFilterIntent.perform()` is not called; test the exact OS build and retain Shortcuts as the fallback automation path.

### Handoff

The app declares `NSUserActivityTypeBrowsingWeb` and routes a received web activity through the same coordinator.

## 7. Validate

Run:

```bash
./Scripts/validate.sh
```

On macOS with XcodeGen installed, this also performs an unsigned Xcode build. The CI workflow performs the same generation and build on a macOS runner.

## 8. Publish an unsigned preview

Unsigned previews are intentionally separate from production releases. Push a
tag such as:

```bash
git tag v0.1.0-preview.1
git push origin v0.1.0-preview.1
```

Tags matching `v*.*.*-preview.*` trigger the unsigned-preview release workflow.
The workflow validates the exact tag format, runs the complete test/build
pipeline, creates an ad-hoc-signed universal app, verifies its signatures and
bundle versions, and publishes a GitHub prerelease with a SHA-256 checksum.
The numeric portion of the tag becomes the Apple-compliant bundle version, so
`v0.1.0-preview.1` produces `CFBundleShortVersionString` `0.1.0`; the preview
sequence remains in the tag, release title, and asset name.

The release and its asset names explicitly say **Unsigned Preview**. These builds
are not Developer ID signed or notarized, so Gatekeeper may prevent normal
installation. They are intended for evaluation and testing rather than
production distribution.

To exercise the same packaging locally without publishing a release:

```bash
./Scripts/package-unsigned-preview.sh 0.1.0-preview.1 1
```

The ZIP and checksum are written under `build/releases/`.

Repository administrators can add required reviewers to the
`unsigned-preview-release` GitHub environment when release tags should require
manual approval before the runner starts.

## 9. Create a signed archive

Set your Apple Team ID and run:

```bash
DEVELOPMENT_TEAM=ABCDE12345 ./Scripts/archive-release.sh
```

The archive is written to:

```text
build/PowerTools.xcarchive
```

Distribution outside the Mac App Store still requires Developer ID signing and notarization. Those credentials are intentionally not embedded in this repository.

## 10. Direct-distribution design

The host application is not sandboxed because it discovers browser profiles and PWAs by reading browser support directories. The embedded Safari and Share extensions are sandboxed.

A Mac App Store edition would require a different profile-access strategy, user-selected security-scoped folders, additional entitlements, and a full App Review assessment. Keep that as a separate distribution configuration rather than silently changing the direct build.
