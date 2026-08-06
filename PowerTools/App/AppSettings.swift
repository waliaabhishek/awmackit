import Foundation
import LinkRouterCore

struct BrowserPresentation: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var isShownInPrompt: Bool
    var promptShortcut: String?
    var order: Int

    init(id: String, isShownInPrompt: Bool = true, promptShortcut: String? = nil, order: Int = 0) {
        self.id = id
        self.isShownInPrompt = isShownInPrompt
        self.promptShortcut = promptShortcut
        self.order = order
    }
}

enum BrowserPickerModifier: String, Codable, CaseIterable, Identifiable, Sendable {
    case function
    case option
    case control
    case shift
    case command
    case disabled

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .function: "Fn / Globe"
        case .option: "Option"
        case .control: "Control"
        case .shift: "Shift"
        case .command: "Command"
        case .disabled: "Disabled"
        }
    }
}

enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case link
    case compass
    case arrowTurn
    case activeBrowser

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .link: "Link"
        case .compass: "Compass"
        case .arrowTurn: "Route Arrow"
        case .activeBrowser: "Primary Browser Icon"
        }
    }
}

struct LinkRouterSettings: Codable, Hashable, Sendable {
    var isEnabled = true
    var primaryTarget: RouteTarget = .prompt
    // Retained for decoding version 1 settings and imported legacy rules.
    var alternativeTarget: RouteTarget = .prompt
    private var alternativeModifier: BrowserPickerModifier = .function
    var browserPickerModifier: BrowserPickerModifier {
        get { alternativeModifier }
        set { alternativeModifier = newValue }
    }
    var showMenuBarIcon = true
    var menuBarIconStyle: MenuBarIconStyle = .activeBrowser
    var launchAtLogin = true

    var removeTrackingParameters = true
    var cleanCopiedLinks = false
    var unwrapEmbeddedRedirects = true
    var expandShortURLs = true
    var resolveUnknownRedirects = false
    var shortURLRedirectLimit = 10
    var customShortenerHosts: [String] = []
    var additionalTrackingParameters: [String] = []
    var allowedTrackingParameters: [String] = []

    var useNativeAppRouting = true
    var googleMeetRoutingEnabled = true
    var googleMeetTarget: RouteTarget?
    var youtubeRoutingEnabled = false
    var youtubeTarget: RouteTarget?
    var enabledNativeAppIDs: Set<String> = Set(
        NativeAppCatalog.builtIns.filter(\.isEnabledByDefault).map(\.id)
    )

    var rules: [LinkRule] = []
    var browserPresentation: [BrowserPresentation] = []

    var browserExtensionAlwaysPrompts = true
    var preservePromptPosition = false
    var promptShowsURL = true
    var historyEnabled = true
    var historyLimit = 500
    var logLevel: RoutingLogLevel = .normal

    var openInBackgroundWhenControlHeld = true
    var optionRevealsPromptActions = true
}

enum RoutingLogLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case normal
    case verbose

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct PowerToolsSettings: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 4

    var schemaVersion = currentSchemaVersion
    var linkRouter = LinkRouterSettings()
}
