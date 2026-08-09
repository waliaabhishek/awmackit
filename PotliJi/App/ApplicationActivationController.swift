import AppKit

@MainActor
final class ApplicationActivationController: NSObject {
    static let shared = ApplicationActivationController()

    private var trackedWindowIDs = Set<ObjectIdentifier>()
    private var isAwaitingWindowPresentation = false
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        for window in NSApp.windows where Self.isUserFacing(window) && window.isVisible {
            trackedWindowIDs.insert(ObjectIdentifier(window))
        }
        reconcileActivationPolicy()
    }

    func prepareForUserWindow() {
        isAwaitingWindowPresentation = true
        applyActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI creates its Settings window asynchronously. If presentation
        // fails, do not strand a windowless menu-bar app in Command-Tab.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.isAwaitingWindowPresentation = false
            self.reconcileActivationPolicy()
        }
    }

    func presentationFailed() {
        isAwaitingWindowPresentation = false
        reconcileActivationPolicy()
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isUserFacing(window) else { return }
        trackedWindowIDs.insert(ObjectIdentifier(window))
        isAwaitingWindowPresentation = false
        applyActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isUserFacing(window) else { return }
        trackedWindowIDs.remove(ObjectIdentifier(window))
        DispatchQueue.main.async { [weak self] in
            self?.reconcileActivationPolicy()
        }
    }

    private func reconcileActivationPolicy() {
        let policy = Self.activationPolicy(
            hasUserFacingWindows: !trackedWindowIDs.isEmpty,
            isAwaitingWindowPresentation: isAwaitingWindowPresentation
        )
        applyActivationPolicy(policy)
    }

    private func applyActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        guard NSApp.setActivationPolicy(policy) else {
            NSLog("PotliJi could not change its activation policy to %ld.", policy.rawValue)
            return
        }
    }

    static func isUserFacing(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    static func activationPolicy(
        hasUserFacingWindows: Bool,
        isAwaitingWindowPresentation: Bool
    ) -> NSApplication.ActivationPolicy {
        hasUserFacingWindows || isAwaitingWindowPresentation ? .regular : .accessory
    }
}
