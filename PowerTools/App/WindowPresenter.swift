import AppKit
import SwiftUI

@MainActor
final class WindowPresenter {
    static let shared = WindowPresenter()
    static let onboardingVersionKey = "PowerTools.onboardingVersion"
    static let currentOnboardingVersion = 1
    private var windows: [String: NSWindow] = [:]

    func showSettings() {
        ApplicationActivationController.shared.prepareForUserWindow()
        guard let applicationMenu = NSApp.mainMenu?.items.first?.submenu,
            let settingsMenuItemIndex = applicationMenu.items.firstIndex(where: {
                $0.keyEquivalent == ","
                    && $0.keyEquivalentModifierMask.contains(.command)
            })
        else {
            ApplicationActivationController.shared.presentationFailed()
            assertionFailure("SwiftUI did not install the Settings menu item")
            NSSound.beep()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            applicationMenu.performActionForItem(at: settingsMenuItemIndex)
        }
    }

    func showHistory() {
        showWindow(id: "history", title: "Link History", size: NSSize(width: 820, height: 520)) {
            AnyView(
                HistoryView()
                    .environmentObject(AppEnvironment.shared)
                    .environmentObject(AppEnvironment.shared.historyStore)
                    .frame(minWidth: 760, minHeight: 480, alignment: .top)
            )
        }
    }

    func showRoutingLog() {
        showWindow(id: "log", title: "Routing Log", size: NSSize(width: 820, height: 520)) {
            AnyView(
                RoutingLogView()
                    .environmentObject(AppEnvironment.shared.routingLogger)
                    .frame(minWidth: 760, minHeight: 480, alignment: .top)
            )
        }
    }

    func showOnboarding() {
        showWindow(id: "onboarding", title: "Welcome to Power Tools", size: NSSize(width: 760, height: 610)) {
            AnyView(
                OnboardingView { [weak self] in
                    UserDefaults.standard.set(
                        Self.currentOnboardingVersion,
                        forKey: Self.onboardingVersionKey
                    )
                    self?.windows["onboarding"]?.close()
                }
                .environmentObject(AppEnvironment.shared)
                .environmentObject(AppEnvironment.shared.settingsStore)
                .environmentObject(AppEnvironment.shared.browserCatalog)
            )
        }
    }

    private func showWindow(
        id: String,
        title: String,
        size: NSSize,
        rootView: () -> AnyView
    ) {
        ApplicationActivationController.shared.prepareForUserWindow()
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView())
        window.contentMinSize = NSSize(
            width: min(size.width, 760),
            height: min(size.height, 480)
        )
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[id] = window
    }
}
