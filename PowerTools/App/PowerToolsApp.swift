import SwiftUI

struct PowerToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        Settings {
            SettingsRootView()
                .environmentObject(environment)
                .environmentObject(environment.settingsStore)
                .environmentObject(environment.browserCatalog)
                .environmentObject(environment.historyStore)
                .frame(minWidth: 780, minHeight: 540)
        }
    }
}
