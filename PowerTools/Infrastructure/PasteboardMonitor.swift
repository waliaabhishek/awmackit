import AppKit
import Foundation
import LinkRouterCore

@MainActor
final class PasteboardMonitor {
    private weak var environment: AppEnvironment?
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var isInspecting = false

    func configure(environment: AppEnvironment) {
        self.environment = environment
    }

    func startIfNeeded() {
        guard let environment,
            environment.settingsStore.settings.linkRouter.cleanCopiedLinks
        else {
            stop()
            return
        }
        if #available(macOS 15.4, *), NSPasteboard.general.accessBehavior == .alwaysDeny {
            environment.settingsStore.settings.linkRouter.cleanCopiedLinks = false
            environment.routingLogger.log(
                .warning,
                stage: "Clipboard",
                "Automatic cleaning stayed off because pasteboard access is denied in System Settings."
            )
            stop()
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() async {
        guard let environment,
            environment.settingsStore.settings.linkRouter.cleanCopiedLinks,
            !isInspecting
        else {
            lastChangeCount = NSPasteboard.general.changeCount
            return
        }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        isInspecting = true
        defer { isInspecting = false }

        let copiedValue: String?
        if #available(macOS 15.4, *) {
            do {
                let requestedPatterns: Set<PartialKeyPath<NSPasteboard.DetectedValues>> = [\.probableWebURL]
                let detectedPatterns = try await pasteboard.detectedPatterns(for: requestedPatterns)
                guard detectedPatterns.contains(\.probableWebURL) else { return }
                copiedValue = try await pasteboard.detectedValues(for: requestedPatterns).probableWebURL
            } catch {
                if pasteboard.accessBehavior == .alwaysDeny {
                    environment.settingsStore.settings.linkRouter.cleanCopiedLinks = false
                    stop()
                    environment.routingLogger.log(
                        .warning,
                        stage: "Clipboard",
                        "Automatic cleaning turned off because pasteboard access was denied."
                    )
                } else {
                    environment.routingLogger.log(.warning, stage: "Clipboard", error.localizedDescription)
                }
                return
            }
        } else {
            copiedValue = pasteboard.string(forType: .string)
        }

        guard let value = copiedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
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
