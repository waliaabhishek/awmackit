import AppKit
import Foundation
import LinkRouterCore

@MainActor
final class RouteTargetResolver {
    private let browserCatalog: BrowserCatalog
    private let nativeAppCatalog = NativeAppCatalog()

    init(browserCatalog: BrowserCatalog) {
        self.browserCatalog = browserCatalog
    }

    func resolveSpecialTarget(_ input: RouteTarget, settings: LinkRouterSettings) -> RouteTarget {
        var current = input
        var visitedKinds: Set<RouteTargetKind> = []

        while [.primaryBrowser, .alternativeBrowser, .systemDefault].contains(current.kind) {
            guard visitedKinds.insert(current.kind).inserted else { return .prompt }
            switch current.kind {
            case .primaryBrowser:
                if let focusTarget = FocusRouteOverride.target(in: browserCatalog) { return focusTarget }
                current = settings.primaryTarget
            case .alternativeBrowser:
                current = settings.alternativeTarget
            case .systemDefault:
                // Power Tools is normally the system default. Calling it again would recurse.
                current = settings.primaryTarget
            default:
                break
            }
        }
        return current
    }

    func promptTargets(settings: LinkRouterSettings) -> [RouteTarget] {
        let discovered = browserCatalog.allTargets
        let presentationByID = settings.browserPresentation.reduce(into: [String: BrowserPresentation]()) {
            result, presentation in
            result[presentation.id] = presentation
        }
        let visible = discovered.filter {
            presentationByID[$0.id]?.isShownInPrompt ?? browserCatalog.isSuggestedPickerTarget($0)
        }
        let sorted = visible.sorted {
            let lhs = presentationByID[$0.id]?.order ?? Int.max
            let rhs = presentationByID[$1.id]?.order ?? Int.max
            if lhs == rhs { return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            return lhs < rhs
        }
        return sorted.isEmpty ? [.copyURL] : sorted
    }

    func webServiceTarget(
        for url: URL,
        settings: LinkRouterSettings
    ) -> (target: RouteTarget, message: String)? {
        guard let host = url.host?.lowercased() else { return nil }

        if settings.googleMeetRoutingEnabled,
            host == "meet.google.com" || host.hasSuffix(".meet.google.com")
        {
            if let configured = settings.googleMeetTarget,
                let resolved = browserCatalog.target(withID: configured.id)
                    ?? configured.applicationPath.map({ _ in configured })
            {
                return (resolved, "Google Meet routed to \(resolved.displayName).")
            }
            if let chromium = automaticChromiumTarget() {
                return (chromium, "Google Meet routed to Chromium-compatible browser \(chromium.displayName).")
            }
        }

        let isYouTube =
            host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
        if settings.youtubeRoutingEnabled, isYouTube,
            let configured = settings.youtubeTarget,
            let resolved = browserCatalog.target(withID: configured.id)
                ?? configured.applicationPath.map({ _ in configured })
        {
            return (resolved, "YouTube routed to \(resolved.displayName).")
        }

        return nil
    }

    func nativeAppTarget(
        for url: URL,
        enabledIDs: Set<String>
    ) -> (definition: NativeAppDefinition, target: RouteTarget, url: URL)? {
        guard let definition = nativeAppCatalog.match(url: url, enabledIDs: enabledIDs),
            let transformed = definition.transformedURL(from: url)
        else { return nil }

        for bundleIdentifier in definition.candidateBundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let target = RouteTarget(
                    id: "native.\(definition.id).\(bundleIdentifier)",
                    kind: .application,
                    displayName: definition.displayName,
                    bundleIdentifier: bundleIdentifier,
                    applicationPath: appURL.path
                )
                return (definition, target, transformed)
            }
        }

        if transformed.scheme != url.scheme,
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: transformed),
            let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        {
            let target = RouteTarget(
                id: "native.\(definition.id).\(bundleIdentifier)",
                kind: .application,
                displayName: definition.displayName,
                bundleIdentifier: bundleIdentifier,
                applicationPath: appURL.path
            )
            return (definition, target, transformed)
        }
        return nil
    }

    private func automaticChromiumTarget() -> RouteTarget? {
        let preferredBundleIdentifiers = [
            "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.google.Chrome.dev",
            "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
            "ai.perplexity.comet", "net.imput.helium", "org.chromium.Thorium", "com.bookry.wavebox",
        ]
        for bundleIdentifier in preferredBundleIdentifiers {
            if let browser = browserCatalog.browsers.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return browser.routeTarget
            }
        }
        return nil
    }
}
