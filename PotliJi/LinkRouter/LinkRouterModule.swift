import ServiceManagement
import SwiftUI

@MainActor
final class LinkRouterModule: AppModule {
    let id = "link-router"
    let displayName = "Link Router"
    let symbolName = "arrow.triangle.branch"

    private unowned let environment: AppEnvironment

    // PotliJi must keep the module running so it can receive system links,
    // maintain its menu, and reconcile login-item state. The user-facing
    // automatic-routing switch controls policy inside LinkRouterCoordinator.
    var isEnabled: Bool { true }

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
