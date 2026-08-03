import ServiceManagement
import SwiftUI

@MainActor
final class LinkRouterModule: PowerToolModule {
    let id = "link-router"
    let displayName = "Link Router"
    let symbolName = "arrow.triangle.branch"

    private unowned let environment: AppEnvironment

    var isEnabled: Bool {
        get { environment.settingsStore.settings.linkRouter.isEnabled }
        set { environment.settingsStore.settings.linkRouter.isEnabled = newValue }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func start() {
        configureLaunchAtLogin()
    }

    func stop() {}

    func settingsView() -> AnyView {
        AnyView(LinkRouterSettingsView())
    }

    func configureLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let shouldLaunch = environment.settingsStore.settings.linkRouter.launchAtLogin
        do {
            if shouldLaunch, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !shouldLaunch, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            environment.routingLogger.log(.warning, stage: "Login Item", error.localizedDescription)
        }
    }
}
