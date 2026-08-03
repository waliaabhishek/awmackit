import AppKit
import LinkRouterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment.shared
    private lazy var statusMenuController = StatusMenuController(environment: environment)
    private let servicesProvider = PowerToolsServices()
    private var isFinishingTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()

        Task { @MainActor in
            await environment.start()
            statusMenuController.start()

            if !environment.settingsStore.settings.linkRouter.showMenuBarIcon {
                statusMenuController.temporarilyReveal()
            }

            if UserDefaults.standard.integer(forKey: WindowPresenter.onboardingVersionKey)
                < WindowPresenter.currentOnboardingVersion
            {
                WindowPresenter.shared.showOnboarding()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let customSchemes = Set(["powertools-link", "powertools"])
        var webURLs: [URL] = []
        for url in urls {
            if let scheme = url.scheme?.lowercased(), customSchemes.contains(scheme) {
                environment.router.handleCustomScheme(url)
            } else {
                webURLs.append(url)
            }
        }
        if !webURLs.isEmpty {
            environment.router.handleIncoming(webURLs, trigger: .systemLink)
        }
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
        else { return false }
        environment.router.handleIncoming([url], trigger: .handoff)
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusMenuController.temporarilyReveal()
        if !flag { WindowPresenter.shared.showSettings() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isFinishingTermination else { return .terminateNow }
        isFinishingTermination = true
        Task { @MainActor in
            try? await environment.settingsStore.saveImmediately()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
