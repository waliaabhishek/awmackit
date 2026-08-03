import AppKit
import LinkRouterCore
import SwiftUI

struct SettingsRootView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general
        case browsers
        case routing
        case privacy
        case extensions
        case advanced

        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .browsers: "Browser Picker"
            case .routing: "Routing"
            case .privacy: "Privacy"
            case .extensions: "Integrations"
            case .advanced: "Advanced"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .browsers: "safari"
            case .routing: "arrow.triangle.branch"
            case .privacy: "hand.raised"
            case .extensions: "link"
            case .advanced: "slider.horizontal.3"
            }
        }
    }

    @AppStorage("settings.selectedPane") private var selectedPaneID = Pane.general.rawValue
    @State private var selectedPane: Pane = {
        let stored = UserDefaults.standard.string(forKey: "settings.selectedPane")
        return stored.flatMap(Pane.init(rawValue:)) ?? .general
    }()

    var body: some View {
        TabView(selection: $selectedPane) {
            settingsPane(GeneralSettingsView(), pane: .general)
            settingsPane(BrowserSettingsView(), pane: .browsers)
            settingsPane(RoutingSettingsView(), pane: .routing)
            settingsPane(PrivacySettingsView(), pane: .privacy)
            settingsPane(ExtensionsSettingsView(), pane: .extensions)
            settingsPane(AdvancedSettingsView(), pane: .advanced)
        }
        .onChange(of: selectedPane) { _, newValue in
            selectedPaneID = newValue.rawValue
        }
    }

    private func settingsPane<Content: View>(_ content: Content, pane: Pane) -> some View {
        content
            .padding(20)
            .frame(width: 900, height: 620)
            .tabItem { Label(pane.title, systemImage: pane.symbol) }
            .tag(pane)
    }
}

struct LinkRouterSettingsView: View {
    var body: some View { SettingsRootView() }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var isDefaultBrowser = DefaultBrowserManager().isPowerToolsDefaultBrowser
    @State private var isChangingDefaultBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: "General",
                subtitle: "Manage Power Tools, its menu-bar presence, and system link-handler setup."
            )

            Form {
                Section("Link Router") {
                    SettingsToggleRow(
                        title: "Apply automatic routing",
                        detail:
                            "When off, links bypass Rules, App Links, and service destinations and use the primary destination. Privacy cleanup remains active.",
                        systemImage: "arrow.triangle.branch",
                        isOn: linkRouterBinding(\.isEnabled)
                    )

                    SettingsControlRow(
                        title: isDefaultBrowser
                            ? "Power Tools is the system link handler"
                            : "Power Tools is not the system link handler",
                        systemImage: isDefaultBrowser ? "checkmark.circle.fill" : "exclamationmark.triangle"
                    ) {
                        Button(isChangingDefaultBrowser ? "Waiting for macOS…" : "Make Default") {
                            makeDefaultBrowser()
                        }
                        .disabled(isDefaultBrowser || isChangingDefaultBrowser)
                    }
                }

                Section("Test Routing") {
                    SettingsControlRow(
                        title: "Open an example link",
                        detail:
                            "Cleans an example.com URL with a tracking parameter, applies your rules, and opens it using the current settings.",
                        systemImage: "checkmark.circle"
                    ) {
                        Button("Open Test Link") { routeTestLink() }
                            .accessibilityLabel("Open a test link")
                    }
                }

                Section("Menu Bar") {
                    SettingsToggleRow(
                        title: "Show menu bar icon",
                        systemImage: "menubar.rectangle",
                        isOn: linkRouterBinding(\.showMenuBarIcon)
                    )
                    SettingsControlRow(
                        title: "Menu bar icon",
                        systemImage: "app.dashed"
                    ) {
                        Picker("Menu bar icon", selection: linkRouterBinding(\.menuBarIconStyle)) {
                            ForEach(MenuBarIconStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .settingsAccessoryPicker()
                    }
                    SettingsToggleRow(
                        title: "Launch at login",
                        systemImage: "power",
                        isOn: Binding(
                            get: { settingsStore.settings.linkRouter.launchAtLogin },
                            set: {
                                settingsStore.settings.linkRouter.launchAtLogin = $0
                                environment.linkRouterModule.configureLaunchAtLogin()
                            }
                        )
                    )
                }

                Section("Setup Guide") {
                    SettingsControlRow(
                        title: "First-use guide",
                        detail: "Review how system links, browser choices, and default-handler setup work.",
                        systemImage: "questionmark.circle"
                    ) {
                        Button("Run Guide Again") { WindowPresenter.shared.showOnboarding() }
                            .accessibilityLabel("Run first-use guide again")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func linkRouterBinding<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }

    private func makeDefaultBrowser() {
        isChangingDefaultBrowser = true
        Task { @MainActor in
            defer { isChangingDefaultBrowser = false }
            do {
                try await DefaultBrowserManager().setPowerToolsAsDefaultBrowser()
                isDefaultBrowser = DefaultBrowserManager().isPowerToolsDefaultBrowser
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func routeTestLink() {
        guard let url = URL(string: "https://example.com/?utm_source=power-tools-setup") else { return }
        let request = RouteRequest(urls: [url], trigger: .manual)
        Task { await environment.router.route(request) }
    }

}

struct RouteTargetPicker: View {
    @EnvironmentObject private var browserCatalog: BrowserCatalog
    let title: String
    @Binding var selection: RouteTarget

    var body: some View {
        Picker(title, selection: $selection) {
            Text(RouteTarget.prompt.displayName).tag(RouteTarget.prompt)
            Divider()
            ForEach(browserCatalog.allTargets) { target in
                Label {
                    Text(target.displayName)
                } icon: {
                    Image(nsImage: browserCatalog.icon(for: target))
                }
                .tag(target)
            }
        }
    }
}
