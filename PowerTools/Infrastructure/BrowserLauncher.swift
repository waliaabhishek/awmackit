import AppKit
import Foundation
import LinkRouterCore

@MainActor
final class BrowserLauncher {
    enum LaunchError: LocalizedError {
        case targetIsNotLaunchable
        case applicationNotFound(String)
        case executableNotFound(String)
        case processFailed(String)
        case safariPrivateUnsupported

        var errorDescription: String? {
            switch self {
            case .targetIsNotLaunchable:
                "The selected route target cannot open a URL."
            case .applicationNotFound(let name):
                "The application “\(name)” could not be found."
            case .executableNotFound(let name):
                "The executable for “\(name)” could not be found."
            case .processFailed(let message):
                "The application could not be launched: \(message)"
            case .safariPrivateUnsupported:
                "Safari private-window routing is unavailable because Power Tools does not request Accessibility permission. Choose another private browser target."
            }
        }
    }

    private unowned let browserCatalog: BrowserCatalog
    init(browserCatalog: BrowserCatalog) {
        self.browserCatalog = browserCatalog
    }

    func open(
        urls: [URL],
        target: RouteTarget,
        inBackground: Bool,
        newWindow: Bool
    ) async throws {
        guard !urls.isEmpty else { return }

        switch target.kind {
        case .application:
            try await openApplication(urls: urls, target: target, inBackground: inBackground, newWindow: newWindow)
        case .browserProfile:
            try await launchProfile(urls: urls, target: target, inBackground: inBackground, newWindow: newWindow)
        case .browserPWA:
            try await launchPWA(urls: urls, target: target, inBackground: inBackground, newWindow: newWindow)
        case .systemDefault:
            for url in urls {
                NSWorkspace.shared.open(url)
            }
        case .discard:
            return
        default:
            throw LaunchError.targetIsNotLaunchable
        }
    }

    private func openApplication(
        urls: [URL],
        target: RouteTarget,
        inBackground: Bool,
        newWindow: Bool
    ) async throws {
        guard let appURL = applicationURL(for: target) else {
            throw LaunchError.applicationNotFound(target.displayName)
        }
        let bundleID = target.bundleIdentifier ?? Bundle(url: appURL)?.bundleIdentifier ?? ""

        if target.openMode == .privateWindow {
            if bundleID == "com.apple.Safari" {
                throw LaunchError.safariPrivateUnsupported
            }
            if BrowserFamilyCatalog.chromiumBundleIDs.contains(bundleID)
                || BrowserFamilyCatalog.firefoxBundleIDs.contains(bundleID)
            {
                var profileTarget = target
                profileTarget.kind = .browserProfile
                try await launchProfile(urls: urls, target: profileTarget, inBackground: inBackground, newWindow: true)
                return
            }
        }

        if newWindow,
            BrowserFamilyCatalog.chromiumBundleIDs.contains(bundleID)
                || BrowserFamilyCatalog.firefoxBundleIDs.contains(bundleID)
        {
            var profileTarget = target
            profileTarget.kind = .browserProfile
            try await launchProfile(urls: urls, target: profileTarget, inBackground: inBackground, newWindow: true)
            return
        }

        // NSWorkspace's URL-opening API reliably launches these browsers from a
        // cold start, but some Chromium/Firefox-family builds only reactivate an
        // already-running process and silently drop the URLs. Start a short-lived
        // command-line instance in that case; the browser's singleton handoff
        // forwards the URLs to the existing process.
        if Self.usesCommandLineHandoff(bundleIdentifier: bundleID),
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        {
            let arguments: [String]
            if BrowserFamilyCatalog.firefoxBundleIDs.contains(bundleID) {
                arguments = urls.flatMap { ["-new-tab", $0.absoluteString] }
            } else {
                arguments = urls.map(\.absoluteString)
            }
            try await handOffToRunningBrowser(
                at: appURL,
                arguments: arguments,
                displayName: target.displayName
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !inBackground
        configuration.addsToRecentItems = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func launchProfile(
        urls: [URL],
        target: RouteTarget,
        inBackground: Bool,
        newWindow: Bool
    ) async throws {
        guard let appURL = applicationURL(for: target) else {
            throw LaunchError.applicationNotFound(target.displayName)
        }
        guard let bundle = Bundle(url: appURL) else { throw LaunchError.applicationNotFound(target.displayName) }
        let bundleID = target.bundleIdentifier ?? bundle.bundleIdentifier ?? ""
        var arguments: [String] = []

        if BrowserFamilyCatalog.chromiumBundleIDs.contains(bundleID) {
            if let profile = target.profileIdentifier, !profile.isEmpty {
                arguments.append("--profile-directory=\(profile)")
            }
            if target.openMode == .privateWindow { arguments.append("--incognito") }
            if newWindow { arguments.append("--new-window") }
            arguments.append(contentsOf: urls.map(\.absoluteString))
        } else if BrowserFamilyCatalog.firefoxBundleIDs.contains(bundleID) {
            if let profile = target.profileName ?? target.profileIdentifier, !profile.isEmpty {
                arguments.append(contentsOf: ["-P", profile])
            }
            if target.openMode == .privateWindow {
                arguments.append("-private-window")
            } else if newWindow {
                arguments.append("-new-window")
            } else {
                arguments.append("-new-tab")
            }
            arguments.append(contentsOf: urls.map(\.absoluteString))
        } else {
            arguments.append(contentsOf: urls.map(\.absoluteString))
        }

        try await launchApplication(at: appURL, arguments: arguments, activates: !inBackground)
    }

    private func launchPWA(
        urls: [URL],
        target: RouteTarget,
        inBackground: Bool,
        newWindow: Bool
    ) async throws {
        if let parentPath = target.applicationPath,
            let appID = target.pwaIdentifier
        {
            let parentTarget = RouteTarget(
                id: target.id,
                kind: .browserProfile,
                displayName: target.displayName,
                bundleIdentifier: target.bundleIdentifier,
                applicationPath: parentPath,
                profileIdentifier: target.profileIdentifier,
                pwaIdentifier: appID
            )
            guard let appURL = applicationURL(for: parentTarget) else {
                throw LaunchError.executableNotFound(target.displayName)
            }
            var arguments: [String] = []
            if let profile = target.profileIdentifier { arguments.append("--profile-directory=\(profile)") }
            arguments.append("--app-id=\(appID)")
            if newWindow { arguments.append("--new-window") }
            arguments.append(contentsOf: urls.map(\.absoluteString))
            try await launchApplication(at: appURL, arguments: arguments, activates: !inBackground)
            return
        }

        guard let pwaPath = target.pwaApplicationPath else {
            throw LaunchError.applicationNotFound(target.displayName)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !inBackground
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                urls,
                withApplicationAt: URL(fileURLWithPath: pwaPath),
                configuration: configuration
            ) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
            }
        }
    }

    private func applicationURL(for target: RouteTarget) -> URL? {
        if let path = target.applicationPath { return URL(fileURLWithPath: path) }
        if let bundleIdentifier = target.bundleIdentifier {
            return browserCatalog.applicationURL(bundleIdentifier: bundleIdentifier)
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        return nil
    }

    private func launchApplication(at url: URL, arguments: [String], activates: Bool) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = activates
        configuration.addsToRecentItems = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func handOffToRunningBrowser(
        at applicationURL: URL,
        arguments: [String],
        displayName: String
    ) async throws {
        guard let executableURL = Bundle(url: applicationURL)?.executableURL else {
            throw LaunchError.executableNotFound(displayName)
        }
        let output = try await AsyncProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: 8
        )
        guard output.terminationStatus == 0 else {
            let standardError = String(decoding: output.standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let standardOutput = String(decoding: output.standardOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = standardError.isEmpty ? standardOutput : standardError
            throw LaunchError.processFailed(
                message.isEmpty ? "The browser handoff exited with status \(output.terminationStatus)." : message
            )
        }
    }

    private static func usesCommandLineHandoff(bundleIdentifier: String) -> Bool {
        BrowserFamilyCatalog.chromiumBundleIDs.contains(bundleIdentifier)
            || BrowserFamilyCatalog.firefoxBundleIDs.contains(bundleIdentifier)
    }

}
