import AppKit
import Foundation
import LinkRouterCore

@MainActor
final class PowerToolsServices: NSObject {
    @objc func openURLs(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        route(pasteboard: pasteboard, forcePrompt: false, error: error)
    }

    @objc func openURLsWithPrompt(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        route(pasteboard: pasteboard, forcePrompt: true, error: error)
    }

    private func route(
        pasteboard: NSPasteboard,
        forcePrompt: Bool,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        guard let text = pasteboard.string(forType: .string) else {
            error?.pointee = "The selected content does not contain text."
            return
        }
        let urls = Self.extractURLs(from: text)
        guard !urls.isEmpty else {
            error?.pointee = "No web URLs were found in the selected content."
            return
        }

        let modifiers = NSEvent.modifierFlags
        let request = RouteRequest(
            urls: urls,
            sourceApplication: SourceAppResolver.shared.resolve(),
            trigger: .service,
            forcePrompt: forcePrompt || modifiers.contains(.option),
            openInBackground: modifiers.contains(.shift)
        )
        Task { await AppEnvironment.shared.router.route(request) }
    }

    static func extractURLs(from text: String) -> [URL] {
        guard text.utf8.count <= 256 * 1_024 else { return [] }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).filter {
            guard let scheme = $0.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
    }
}
