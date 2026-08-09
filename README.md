# PotliJi

A macOS menu-bar application whose current module, **Link Router**, routes links through the browser, profile, web app, or native application the user chooses.

This is a clean-room implementation of the product category represented by Velja. It does not contain Velja source code, artwork, branding, settings files, or other proprietary assets.

## What is included

The project contains a native Swift/AppKit/SwiftUI host app, a portable Swift package for routing logic, a Safari WebExtension, a macOS Share extension, and unpacked Chromium/Firefox WebExtensions.

The Link Router currently implements the following source-level capabilities:

- Registration as the `http` and `https` handler and a one-click “Make Default” action.
- Automatic discovery of installed browsers.
- Chromium-family profiles, Firefox/Zen profiles, Brave Origin profiles, and Chromium PWAs.
- A keyboard-driven browser picker with browser icons, custom letter shortcuts, number shortcuts, arrows, Tab cycling, Copy, Share, new-window routing, background routing, and one-click domain-rule creation.
- Primary and alternative browser targets with a configurable modifier key.
- URL rules based on host, subdomain, complete URL, prefix, suffix, path, scheme, query parameter, regular expression, and source application.
- Positive source-app alternatives and negated source-app exclusions.
- Rule destinations for browsers, profiles, PWAs, any selected macOS application, the primary/alternative target, the picker, Copy, Share, or discard.
- User-authored JavaScript URL transforms using the `$.url` / `$.sourceApp` model, isolated in a deadline-enforced helper process.
- Per-rule new-window and background launch behavior.
- Removal of more than 200 tracking keys, plus site-specific cleanup for X/Twitter, Facebook, TikTok, YouTube, and Amazon.
- Embedded redirect unwrapping and recognized short-link expansion that never prefetches the arbitrary final destination.
- Optional automatic cleanup of web URLs copied to the clipboard.
- Built-in routing definitions for the current Velja service list: Airtable, Amazon Chime, App Store, Apple Music, Around, Asana, ClickUp, Discord, Figma, Front, Jitsi Meet, Linear, Mastodon, Microsoft Teams, Miro, Notion, Pop, Reddit, Slite, Spotify, Telegram, TIDAL, Trello, X/Twitter, Zeplin, and Zoom.
- Google Meet routing to an automatic Chromium browser or a selected browser, PWA, or application.
- YouTube routing to a selected browser, PWA, or application.
- Private/incognito launch targets for Chromium-family browsers, Firefox, and Zen without Accessibility automation.
- Safari, Chromium, and Firefox browser-extension sources, with toolbar/context-menu handoff and a separate force-picker action.
- macOS Share extension and Services integration for one or many selected URLs.
- App Intents and App Shortcuts, a Focus Filter intent, Handoff, and a custom URL command scheme.
- Menu-bar browser switching and Option-launch behavior.
- Bounded journaled local history with corruption recovery, searchable diagnostics, and JSON rule import/export.
- Songlink creation from a copied music URL.
- A module registry and `LinkRouterModule` boundary for integration into the broader PotliJi application.

See [FEATURE_PARITY.md](FEATURE_PARITY.md) for the detailed audit and [ARCHITECTURE.md](ARCHITECTURE.md) for the integration model.

## Build on a Mac

Requirements:

- macOS 14 or later.
- Xcode 16 or later.
- Swift 5.10 or later.
- XcodeGen 2.40 or later.
- Python 3.
- An Apple Developer team for a signed local build and extension testing.

```bash
brew install xcodegen
cd potliji
./Scripts/bootstrap.sh
open PotliJi.xcodeproj
```

In Xcode:

1. Select a Development Team for `PotliJi`, `LinkRouterSafariExtension`, and `LinkRouterShareExtension`.
2. Change the three example bundle identifiers if they conflict with identifiers already registered to your team.
3. Run the `PotliJi` scheme.
4. In the app, select **Make Default**.
5. Enable the Safari extension in Safari settings when testing links that originate inside Safari.

Detailed signing, extension, and archive steps are in [BUILDING.md](BUILDING.md).

Version tags ending in `-preview.N`, such as `v0.1.0-preview.1`, publish a
clearly labeled, ad-hoc-signed GitHub prerelease for evaluation. These preview
builds are not Developer ID signed or notarized. See [BUILDING.md](BUILDING.md)
for the release contract and local packaging command.

### Quick local test build

To produce an ad-hoc-signed build that runs locally without configuring an
Apple Developer team:

```bash
./Scripts/build-local.sh
open build/PotliJi.app
```

The script uses `/Applications/Xcode.app` by default, regenerates the Xcode
project, builds the host and both extensions, and verifies the resulting code
signature. Set `DEVELOPER_DIR` first when Xcode is installed elsewhere.

## Command-line validation

```bash
./Scripts/validate.sh
```

The validation script:

- Builds the unpacked browser-extension folders.
- Validates all JSON manifests and JavaScript extension sources.
- Validates the XcodeGen YAML specification, property-list files, and entitlements.
- Runs the portable `LinkRouterCore` test suite.
- Parses every macOS Swift source file.
- Checks every shell script.
- On macOS with XcodeGen installed, also generates and builds the Xcode project without code signing.

## Project layout

```text
potliji/
├── PotliJi/                         macOS host application
│   ├── App/                            app shell and module registry
│   ├── Infrastructure/                 browser discovery, launching, persistence
│   └── LinkRouter/                     coordinator, UI, services, intents
├── Packages/LinkRouterCore/            portable routing/sanitization package
├── Extensions/
│   ├── SafariWebExtension/             embedded Safari extension
│   └── ShareExtension/                 macOS Share extension
├── BrowserExtensions/LinkRouter/
│   ├── common/                         shared Safari/Chromium/Firefox code
│   └── dist/                           generated browser distributions
├── Config/                             plists and entitlements
├── Scripts/                            build, validation, and archive scripts
└── project.yml                         XcodeGen project definition
```

## Verification boundary

`./Scripts/validate.sh` covers the portable core, browser-extension sources, generated Xcode project, host application, app extensions, strict-concurrency diagnostics, and hosted unit tests when full Xcode is available. Release verification must still exercise browser command-line delivery, current Firefox/Zen profile formats, extension activation, Focus behavior, and default-browser registration on every supported macOS/browser combination; compilation alone cannot prove those external integrations.

## Product boundaries

PotliJi is the sole product and host identity. Link Router is the current module; future capabilities should be separate `AppModule` implementations with module-owned names and neutral shared infrastructure.

The repository intentionally does not include licensing, payments, analytics, update infrastructure, localization, notarization credentials, store listings, extension-store publication, or Velja-compatible branding.
