import AppKit
import Foundation

struct DefaultBrowserManager {
    enum DefaultBrowserError: LocalizedError {
        case missingBundleIdentifier
        case requestFailed(scheme: String, underlying: Error)
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .missingBundleIdentifier:
                "Power Tools does not have a bundle identifier."
            case .requestFailed(let scheme, let underlying):
                "macOS could not make Power Tools the \(scheme.uppercased()) link handler. \(underlying.localizedDescription)"
            case .verificationFailed:
                "macOS completed the request, but Power Tools is not the handler for both HTTP and HTTPS links."
            }
        }
    }

    private let webSchemes = ["http", "https"]

    var currentHTTPHandler: String? { currentHandler(for: "http") }
    var currentHTTPSHandler: String? { currentHandler(for: "https") }

    var isPowerToolsDefaultBrowser: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        return currentHTTPHandler == bundleIdentifier && currentHTTPSHandler == bundleIdentifier
    }

    private func currentHandler(for scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://example.com"),
            let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else {
            return nil
        }
        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    func setPowerToolsAsDefaultBrowser() async throws {
        guard !isPowerToolsDefaultBrowser else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw DefaultBrowserError.missingBundleIdentifier
        }

        // This API performs the macOS user-consent flow before changing a handler.
        // LSSetDefaultHandlerForURLScheme is deprecated and can fail with permErr (-54)
        // instead of presenting that consent UI on current macOS releases.
        for scheme in webSchemes {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: Bundle.main.bundleURL,
                    toOpenURLsWithScheme: scheme
                )
            } catch {
                throw DefaultBrowserError.requestFailed(scheme: scheme, underlying: error)
            }
        }

        guard currentHTTPHandler == bundleIdentifier,
            currentHTTPSHandler == bundleIdentifier
        else {
            throw DefaultBrowserError.verificationFailed
        }
    }
}
