import AppIntents
import AppKit
import LinkRouterCore

struct OpenURLWithPowerToolsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open URL with Power Tools"
    static let description = IntentDescription(
        "Route one or more URLs through Power Tools rules, profiles, privacy cleaning, and native-app routing.")
    static let openAppWhenRun = false

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Browser or Profile")
    var browser: BrowserTargetEntity?

    @Parameter(title: "Show Browser Picker", default: false)
    var showPicker: Bool

    @Parameter(title: "Open in New Window", default: false)
    var newWindow: Bool

    @Parameter(title: "Open in Background", default: false)
    var background: Bool

    func perform() async throws -> some IntentResult {
        await AppEnvironment.shared.browserCatalog.loadIfNeeded()
        let forcedTarget = await MainActor.run {
            browser.flatMap { AppEnvironment.shared.browserCatalog.target(withID: $0.id) }
        }
        let request = RouteRequest(
            urls: [url],
            trigger: .shortcut,
            forcePrompt: showPicker,
            forcedTarget: forcedTarget,
            openInBackground: background,
            openInNewWindow: newWindow,
            bypassRules: forcedTarget != nil
        )
        await AppEnvironment.shared.router.route(request)
        return .result()
    }
}

struct CleanURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean URL"
    static let description = IntentDescription(
        "Remove tracking parameters and unwrap embedded redirects without opening the URL.")
    static let openAppWhenRun = false

    @Parameter(title: "URL")
    var url: URL

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard url.absoluteString.utf8.count <= URLSanitizer.maximumInputBytes else {
            throw IntentError.message("The URL is too large to clean safely.")
        }
        await AppEnvironment.shared.settingsStore.loadIfNeeded()
        let sanitizer = await MainActor.run { () -> URLSanitizer in
            let settings = AppEnvironment.shared.settingsStore.settings.linkRouter
            return URLSanitizer(
                additionalParameters: Set(settings.additionalTrackingParameters),
                allowedParameters: Set(settings.allowedTrackingParameters),
                removeTrackingParameters: settings.removeTrackingParameters,
                unwrapRedirects: settings.unwrapEmbeddedRedirects
            )
        }
        let result = await Task.detached(priority: .userInitiated) {
            sanitizer.sanitize(url).url.absoluteString
        }.value
        return .result(value: result)
    }
}

struct OpenClipboardURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Clipboard URL"
    static let description = IntentDescription("Find web links on the clipboard and route them through Power Tools.")
    static let openAppWhenRun = false

    @Parameter(title: "Show Browser Picker", default: true)
    var showPicker: Bool

    func perform() async throws -> some IntentResult {
        let urls = await MainActor.run { () -> [URL] in
            guard let text = NSPasteboard.general.string(forType: .string) else { return [] }
            return PowerToolsServices.extractURLs(from: text)
        }
        guard !urls.isEmpty else {
            throw IntentError.message("The clipboard does not contain a web URL.")
        }
        let request = RouteRequest(urls: urls, trigger: .shortcut, forcePrompt: showPicker)
        await AppEnvironment.shared.router.route(request)
        return .result()
    }
}

struct SetPrimaryBrowserIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Primary Browser"
    static let description = IntentDescription("Change the primary browser or browser profile used by Power Tools.")
    static let openAppWhenRun = false

    @Parameter(title: "Browser or Profile")
    var browser: BrowserTargetEntity

    func perform() async throws -> some IntentResult {
        await AppEnvironment.shared.browserCatalog.loadIfNeeded()
        let updated = await MainActor.run { () -> Bool in
            guard let target = AppEnvironment.shared.browserCatalog.target(withID: browser.id) else { return false }
            AppEnvironment.shared.settingsStore.settings.linkRouter.primaryTarget = target
            return true
        }
        guard updated else { throw IntentError.message("That browser is no longer installed.") }
        return .result()
    }
}

private enum IntentError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
