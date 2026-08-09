# Architecture

## Goal

The Link Router is implemented as a self-contained PotliJi module, not as a one-off application. It owns link-specific routing, browser discovery, prompt UI, privacy cleanup, and integrations while depending on a small host shell for lifecycle, settings, windows, and menu-bar presentation.

The naming hierarchy is deliberately shallow:

```text
PotliJi                         product and macOS application
├── Link Router                current module
└── File Router                future module; not implemented here
```

There is no second umbrella or intermediate suite layer. Product identity uses `PotliJi`, module-owned code uses its module name, and shared host infrastructure uses neutral `App*` or role-based names.

## Layering

### `LinkRouterCore`

A portable Swift package containing no AppKit or browser-launching code:

- Routing models.
- URL and source-application matchers.
- Ordered rule evaluation.
- Route targets.
- Redirect unwrapping.
- Tracking-parameter sanitization.
- Shortener registry.
- Native-app URL definitions and transforms.
- Rule import/export.

This package is the stable domain layer and should remain reusable by a command-line tester, future daemon/helper, or settings migration tool.

### Host application

`PotliJi/App` provides:

- `PotliJiApp` and the application delegate.
- `AppEnvironment`, the composition root.
- `ModuleRegistry` and `AppModule`.
- JSON-backed settings.
- Menu-bar and window presentation.

Future utilities should register their own modules without adding unrelated behavior to `LinkRouterCoordinator`.

### Link Router infrastructure

`PotliJi/Infrastructure` provides macOS-specific adapters:

- Browser/application discovery through Launch Services and bundle metadata.
- Chromium, Firefox/Zen, and PWA profile discovery.
- Browser/profile/PWA launching.
- Default-browser registration.
- Source-application resolution.
- Short-link network resolution.
- JavaScriptCore URL transforms.
- History and diagnostics.
- Clipboard monitoring.
- Focus override storage.

### Link Router module

`PotliJi/LinkRouter` contains:

- `LinkRouterModule`, the PotliJi integration boundary.
- `LinkRouterCoordinator`, the routing pipeline.
- Custom URL command parsing.
- macOS Services.
- Prompt/settings/history/log UI.
- App Intents and Focus Filter intent.

### Extensions

- Safari, Chromium, and Firefox consume one shared WebExtension HTML/JavaScript source with browser-specific manifests.
- The Safari WebExtension is built as an app extension and embedded in the signed host app.
- The Share extension hands URLs to the host through the custom command scheme.
- Disposable developer distributions are generated for all three browsers; deterministic Chromium and Firefox ZIPs are produced separately for store upload.

## Routing pipeline

For each incoming URL, the coordinator performs:

```text
receive URL(s)
  → identify trigger and source application
  → apply modifier-key overrides
  → expand recognized short URL when enabled
  → unwrap embedded redirect when enabled
  → remove tracking data when enabled
  → evaluate ordered user rules
  → execute optional JavaScript transform
  → apply Google Meet / YouTube service routing
  → apply enabled native-app routing
  → resolve primary, alternative, Focus, or picker target
  → launch, copy, share, or discard
  → append local history and diagnostics
```

User rules precede built-in service/native-app routing. An explicitly forced target bypasses rules. Primary/alternative target resolution detects cycles and safely falls back to the picker.

## State and persistence

User data is stored under the user's Application Support directory:

```text
~/Library/Application Support/PotliJi/settings.json
~/Library/Application Support/PotliJi/link-history.json
```

Settings export includes module configuration and rules. It does not include history or diagnostics.

At startup, migration runs before either persistence store is created. The supported files from `~/Library/Application Support/PowerTools/` are copied into the canonical directory through temporary files and verified byte-for-byte; the historical directory is never deleted. Existing canonical files always win, while missing canonical files may be filled from historical data. Unsupported or unreadable historical files remain untouched.

Preferences previously scoped to `com.abhi.PowerTools` are copied key-by-key only when their canonical equivalents are absent. This covers onboarding state, picker position, the active Focus target, and the selected settings pane. Migrated `launchAtLogin` settings are reconciled after settings load. Default HTTP/HTTPS ownership is never migrated or seized; the user may need to select PotliJi once after the bundle-identifier change.

New integrations emit `potliji-link://` (or `potliji://` for product-level commands). The `powertools-link://` and `powertools://` schemes remain registered only as compatibility aliases and reach the same command parser.

The browser catalog is rebuilt from installed applications and browser support directories rather than persisted as authoritative state. Stored targets keep both stable identifiers and paths so custom applications continue to work when they are not classified as browsers.

## Module integration contract

The PotliJi host uses this shared contract:

```swift
@MainActor
protocol AppModule: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var isEnabled: Bool { get }

    func start()
    func stop()
    func settingsView() -> AnyView
}
```

The host centralizes:

- Menu-bar ownership.
- Command-palette registration.
- Launch-at-login state.
- Permission explanations.
- Settings migration and export.
- Product-level infrastructure that may be added explicitly in the future.

The Link Router should continue to own:

- HTTP/HTTPS and custom command handling.
- Browser and profile catalog.
- Link rules and transformations.
- Link prompt.
- Link privacy and native-app routing.
- Browser/share/service/shortcut integrations.

## Concurrency model

macOS UI and Launch Services operations are main-actor isolated. Short-link requests use async URLSession APIs. The portable core uses value types and is `Sendable`.

JavaScript transforms currently execute synchronously through JavaScriptCore because they are user-authored local configuration. Treat imported rule files as executable configuration and review scripts before importing them. A hardened public release should add an execution deadline or move transforms behind a killable helper process.

## Extending the router

Prefer new capability behind protocols or small adapters rather than expanding the coordinator indefinitely. Likely future seams include:

- `BrowserDiscovering`
- `URLLaunching`
- `ShortURLResolving`
- `URLTransforming`
- `HistoryPersisting`
- `PermissionChecking`

Those interfaces would also make full macOS integration tests easier to run with deterministic fakes.
