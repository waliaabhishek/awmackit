import AppKit
import Combine
import CoreServices
import Foundation
import LinkRouterCore

@MainActor
final class BrowserCatalog: ObservableObject {
    private struct DiscoveryDetails: Sendable {
        let profiles: [BrowserProfile]
        let pwas: [BrowserPWA]
    }

    @Published private(set) var browsers: [BrowserInstallation] = []
    @Published private(set) var profiles: [BrowserProfile] = []
    @Published private(set) var pwas: [BrowserPWA] = []
    @Published private(set) var isRefreshing = false
    private var applicationRefreshTask: Task<[BrowserInstallation], Never>?
    private var applicationRefreshID: UUID?
    private var detailRefreshTask: Task<DiscoveryDetails, Never>?
    private var detailRefreshID: UUID?
    private var refreshActivityCount = 0
    private var hasLoadedDetails = false

    var normalTargets: [RouteTarget] {
        browsers.map(\.routeTarget) + profiles.map(\.routeTarget) + pwas.map(\.routeTarget)
    }

    var privateTargets: [RouteTarget] {
        (browsers.map(\.routeTarget) + profiles.map(\.routeTarget)).compactMap { target in
            guard let bundleIdentifier = target.bundleIdentifier,
                BrowserFamilyCatalog.supportsPrivateWindows(bundleIdentifier)
            else { return nil }
            var privateTarget = target
            privateTarget.id += ".private"
            privateTarget.displayName += " — Private"
            privateTarget.openMode = .privateWindow
            return privateTarget
        }
    }

    var allTargets: [RouteTarget] { normalTargets + privateTargets }

    func isSuggestedPickerTarget(_ target: RouteTarget) -> Bool {
        guard target.kind == .application,
            target.openMode == .normal,
            let bundleIdentifier = target.bundleIdentifier
        else {
            return false
        }
        return BrowserFamilyCatalog.isRecognizedBrowser(bundleIdentifier)
    }

    func loadIfNeeded() async {
        await loadApplicationsIfNeeded()
        guard !hasLoadedDetails else { return }
        beginRefreshActivity()
        defer { endRefreshActivity() }
        await refreshDetails(for: browsers)
    }

    /// Loads only Launch Services application registrations. Profile and PWA
    /// discovery intentionally stays off the URL-routing startup path.
    func loadApplicationsIfNeeded() async {
        guard browsers.isEmpty else { return }
        beginRefreshActivity()
        defer { endRefreshActivity() }
        _ = await refreshApplications()
    }

    func refresh() async {
        beginRefreshActivity()
        defer { endRefreshActivity() }

        let installations = await refreshApplications()
        await refreshDetails(for: installations)
    }

    func refreshDetailsInBackground() {
        guard !browsers.isEmpty else { return }
        let installations = browsers
        Task { [weak self] in
            guard let self else { return }
            self.beginRefreshActivity()
            defer { self.endRefreshActivity() }
            await self.refreshDetails(for: installations)
        }
    }

    func target(withID id: String) -> RouteTarget? {
        allTargets.first(where: { $0.id == id })
    }

    func installation(bundleIdentifier: String) -> BrowserInstallation? {
        browsers.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        installation(bundleIdentifier: bundleIdentifier)?.applicationURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func icon(for target: RouteTarget) -> NSImage {
        if let path = target.pwaApplicationPath ?? target.applicationPath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let bundleIdentifier = target.bundleIdentifier,
            let url = applicationURL(bundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "safari", accessibilityDescription: target.displayName) ?? NSImage()
    }

    private nonisolated static func discoverBrowserInstallations() -> [BrowserInstallation] {
        var applicationURLs = Set<URL>()
        let probe = URL(string: "https://example.com") as CFURL?
        if let probe, let result = LSCopyApplicationURLsForURL(probe, .all)?.takeRetainedValue() {
            for case let url as URL in result as NSArray {
                applicationURLs.insert(url.standardizedFileURL)
            }
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        return applicationURLs.compactMap { url in
            guard let bundle = Bundle(url: url),
                let bundleIdentifier = bundle.bundleIdentifier,
                bundleIdentifier != ownBundleID
            else { return nil }
            let displayName =
                (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            return BrowserInstallation(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                applicationURL: url,
                version: version,
                supportsChromiumProfiles: BrowserFamilyCatalog.chromiumBundleIDs.contains(bundleIdentifier),
                supportsFirefoxProfiles: BrowserFamilyCatalog.firefoxBundleIDs.contains(bundleIdentifier)
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func refreshApplications() async -> [BrowserInstallation] {
        let task: Task<[BrowserInstallation], Never>
        let refreshID: UUID
        if let applicationRefreshTask {
            task = applicationRefreshTask
            refreshID = applicationRefreshID ?? UUID()
        } else {
            let newRefreshID = UUID()
            let newTask = Task.detached(priority: .userInitiated) {
                Self.discoverBrowserInstallations()
            }
            applicationRefreshTask = newTask
            applicationRefreshID = newRefreshID
            task = newTask
            refreshID = newRefreshID
        }

        let installations = await task.value
        guard applicationRefreshID == refreshID else { return installations }
        applicationRefreshTask = nil
        applicationRefreshID = nil
        if browsers != installations {
            browsers = installations
            profiles = []
            pwas = []
            hasLoadedDetails = false
        }
        return installations
    }

    private func refreshDetails(for installations: [BrowserInstallation]) async {
        let task: Task<DiscoveryDetails, Never>
        let refreshID: UUID
        if let detailRefreshTask, browsers == installations {
            task = detailRefreshTask
            refreshID = detailRefreshID ?? UUID()
        } else {
            let newRefreshID = UUID()
            let newTask = Task.detached(priority: .utility) {
                let profileDiscovery = ProfileDiscovery()
                return DiscoveryDetails(
                    profiles: installations.flatMap(profileDiscovery.discoverProfiles(for:)),
                    pwas: profileDiscovery.discoverPWAs(browsers: installations)
                )
            }
            detailRefreshTask = newTask
            detailRefreshID = newRefreshID
            task = newTask
            refreshID = newRefreshID
        }

        let details = await task.value
        guard detailRefreshID == refreshID else { return }
        detailRefreshTask = nil
        detailRefreshID = nil
        guard browsers == installations else { return }
        profiles = details.profiles
        pwas = details.pwas
        hasLoadedDetails = true
    }

    private func beginRefreshActivity() {
        refreshActivityCount += 1
        isRefreshing = true
    }

    private func endRefreshActivity() {
        refreshActivityCount = max(0, refreshActivityCount - 1)
        isRefreshing = refreshActivityCount > 0
    }

}

enum BrowserFamilyCatalog {
    static func isRecognizedBrowser(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier == "com.apple.Safari"
            || chromiumBundleIDs.contains(bundleIdentifier)
            || firefoxBundleIDs.contains(bundleIdentifier)
    }

    static func supportsPrivateWindows(_ bundleIdentifier: String) -> Bool {
        chromiumBundleIDs.contains(bundleIdentifier) || firefoxBundleIDs.contains(bundleIdentifier)
    }

    static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.google.Chrome.dev",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly", "com.brave.Browser.origin",
        "com.vivaldi.Vivaldi", "com.vivaldi.Vivaldi.snapshot", "org.chromium.Chromium", "ai.perplexity.comet",
        "net.imput.helium", "org.chromium.Thorium", "com.bookry.wavebox",
    ]

    static let firefoxBundleIDs: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "app.zen-browser.zen", "io.github.zen_browser.zen",
    ]
}
