import AppKit
import Foundation
import LinkRouterCore

@MainActor
final class PasteboardMonitor {
    private weak var environment: AppEnvironment?
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    func configure(environment: AppEnvironment) {
        self.environment = environment
    }

    func startIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let environment,
            environment.settingsStore.settings.linkRouter.cleanCopiedLinks
        else {
            lastChangeCount = NSPasteboard.general.changeCount
            return
        }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            value.utf8.count <= 16_384,
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else { return }

        let settings = environment.settingsStore.settings.linkRouter
        let sanitizer = URLSanitizer(
            additionalParameters: Set(settings.additionalTrackingParameters),
            allowedParameters: Set(settings.allowedTrackingParameters),
            removeTrackingParameters: settings.removeTrackingParameters,
            unwrapRedirects: settings.unwrapEmbeddedRedirects
        )
        let sanitized = sanitizer.sanitize(url).url
        guard sanitized != url else { return }
        pasteboard.clearContents()
        pasteboard.setString(sanitized.absoluteString, forType: .string)
        lastChangeCount = pasteboard.changeCount
        environment.routingLogger.log(stage: "Clipboard", "Removed tracking data from a copied URL.")
    }
}
