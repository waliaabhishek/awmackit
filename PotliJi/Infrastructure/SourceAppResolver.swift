import AppKit
import Carbon
import Foundation
import LinkRouterCore

@MainActor
final class SourceAppResolver {
    static let shared = SourceAppResolver()

    private var lastExternalApplication: NSRunningApplication?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                application.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            MainActor.assumeIsolated {
                self?.lastExternalApplication = application
            }
        }
    }

    func resolve() -> SourceApplication? {
        if let sender = appleEventSender(), sender.bundleIdentifier != Bundle.main.bundleIdentifier {
            return sourceApplication(from: sender)
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            return sourceApplication(from: frontmost)
        }
        if let lastExternalApplication {
            return sourceApplication(from: lastExternalApplication)
        }
        return nil
    }

    private func appleEventSender() -> NSRunningApplication? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return nil }
        // 'spid' is the sender process identifier Apple-event attribute.
        let senderPIDKeyword: AEKeyword = 0x73706964
        guard let descriptor = event.attributeDescriptor(forKeyword: senderPIDKeyword) else { return nil }
        let pid = pid_t(descriptor.int32Value)
        guard pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    private func sourceApplication(from application: NSRunningApplication) -> SourceApplication {
        SourceApplication(
            bundleIdentifier: application.bundleIdentifier,
            name: application.localizedName ?? application.bundleIdentifier ?? "Unknown App",
            processIdentifier: application.processIdentifier
        )
    }
}
