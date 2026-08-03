import AppKit
import Foundation
import LinkRouterCore

struct BrowserInstallation: Identifiable, Hashable, Sendable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL
    let version: String?
    let supportsChromiumProfiles: Bool
    let supportsFirefoxProfiles: Bool

    var routeTarget: RouteTarget {
        RouteTarget(
            id: "app.\(bundleIdentifier)",
            kind: .application,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            applicationPath: applicationURL.path
        )
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

struct BrowserProfile: Identifiable, Hashable, Sendable {
    let id: String
    let browserBundleIdentifier: String
    let browserName: String
    let browserApplicationURL: URL
    let profileIdentifier: String
    let profileName: String
    let kind: ProfileKind

    enum ProfileKind: String, Hashable, Sendable {
        case chromium
        case firefox
    }

    var displayName: String { "\(browserName) — \(profileName)" }

    var routeTarget: RouteTarget {
        RouteTarget(
            id: id,
            kind: .browserProfile,
            displayName: displayName,
            bundleIdentifier: browserBundleIdentifier,
            applicationPath: browserApplicationURL.path,
            profileIdentifier: profileIdentifier,
            profileName: profileName
        )
    }
}

struct BrowserPWA: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let applicationURL: URL
    let parentBrowserBundleIdentifier: String?
    let parentBrowserApplicationURL: URL?
    let profileIdentifier: String?
    let appIdentifier: String?

    var routeTarget: RouteTarget {
        RouteTarget(
            id: id,
            kind: .browserPWA,
            displayName: displayName,
            bundleIdentifier: parentBrowserBundleIdentifier,
            applicationPath: parentBrowserApplicationURL?.path,
            profileIdentifier: profileIdentifier,
            pwaIdentifier: appIdentifier,
            pwaApplicationPath: applicationURL.path
        )
    }
}
