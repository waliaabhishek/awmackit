import Foundation
import LinkRouterCore

struct CustomURLCommand {
    enum Action {
        case open(RouteRequest)
        case cleanAndCopy(URL)
        case showSettings
        case showHistory
    }

    enum ParseError: LocalizedError {
        case unsupportedCommand
        case missingURL

        var errorDescription: String? {
            switch self {
            case .unsupportedCommand: "The Power Tools URL command is not supported."
            case .missingURL: "The command did not contain a URL."
            }
        }
    }

    let action: Action

    @MainActor
    init(url: URL, browserCatalog: BrowserCatalog) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ParseError.unsupportedCommand
        }
        let command =
            (components.host?.isEmpty == false
            ? components.host : components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))?.lowercased()
        let queryItems = components.queryItems ?? []
        let values = Dictionary(grouping: queryItems, by: { $0.name.lowercased() })
        func first(_ name: String) -> String? { values[name.lowercased()]?.first?.value }
        func all(_ name: String) -> [String] { values[name.lowercased(), default: []].compactMap(\.value) }
        func flag(_ name: String) -> Bool {
            guard let items = values[name.lowercased()], let item = items.first else { return false }
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                !value.isEmpty
            else { return true }
            return ["1", "true", "yes", "on"].contains(value)
        }

        switch command {
        case "open", nil:
            let urls = all("url").compactMap(Self.webURL(from:))
            guard !urls.isEmpty else { throw ParseError.missingURL }
            let appID = first("app")
            let profile = first("profile")
            let forcedTarget: RouteTarget?
            if let appID {
                if let profile,
                    let discovered = browserCatalog.profiles.first(where: {
                        $0.browserBundleIdentifier == appID
                            && $0.profileName.caseInsensitiveCompare(profile) == .orderedSame
                    })
                {
                    forcedTarget = discovered.routeTarget
                } else if let installation = browserCatalog.installation(bundleIdentifier: appID) {
                    if let profile {
                        forcedTarget = RouteTarget(
                            id: "profile.\(appID).\(profile)",
                            kind: .browserProfile,
                            displayName: "\(installation.displayName) — \(profile)",
                            bundleIdentifier: appID,
                            applicationPath: installation.applicationURL.path,
                            profileIdentifier: profile,
                            profileName: profile
                        )
                    } else {
                        forcedTarget = installation.routeTarget
                    }
                } else {
                    forcedTarget = RouteTarget(
                        id: "app.\(appID)",
                        kind: .application,
                        displayName: appID,
                        bundleIdentifier: appID
                    )
                }
            } else {
                forcedTarget = nil
            }

            let trigger: RouterTrigger
            switch first("source")?.lowercased() {
            case "browser-extension": trigger = .browserExtension
            case "share-extension": trigger = .shareExtension
            case "service": trigger = .service
            case "shortcut": trigger = .shortcut
            case "handoff": trigger = .handoff
            default: trigger = .customURLScheme
            }
            action = .open(
                RouteRequest(
                    urls: urls,
                    trigger: trigger,
                    forcePrompt: flag("prompt"),
                    forcedTarget: forcedTarget,
                    openInBackground: flag("background"),
                    openInNewWindow: flag("newwindow"),
                    bypassRules: forcedTarget != nil
                ))
        case "clean", "clean-and-copy":
            guard let raw = first("url"), let targetURL = Self.webURL(from: raw) else { throw ParseError.missingURL }
            action = .cleanAndCopy(targetURL)
        case "settings":
            action = .showSettings
        case "history":
            action = .showHistory
        default:
            throw ParseError.unsupportedCommand
        }
    }

    private static func webURL(from value: String) -> URL? {
        guard let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }
}
