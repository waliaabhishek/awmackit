import AppKit
import LinkRouterCore
import SwiftUI

struct SettingsRootView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general
        case browsers
        case rules
        case apps
        case privacy
        case extensions
        case advanced

        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .browsers: "Browsers & Profiles"
            case .rules: "Rules"
            case .apps: "Native Apps"
            case .privacy: "Privacy"
            case .extensions: "Integrations"
            case .advanced: "Advanced"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .browsers: "safari"
            case .rules: "arrow.triangle.branch"
            case .apps: "app.badge"
            case .privacy: "hand.raised"
            case .extensions: "link"
            case .advanced: "slider.horizontal.3"
            }
        }
    }

    @State private var selection: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralSettingsView()
                case .browsers: BrowserSettingsView()
                case .rules: RulesSettingsView()
                case .apps: NativeAppsSettingsView()
                case .privacy: PrivacySettingsView()
                case .extensions: ExtensionsSettingsView()
                case .advanced: AdvancedSettingsView()
                }
            }
            .padding(20)
        }
        .navigationTitle("Power Tools")
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
        Form {
            Section("Link Router") {
                Toggle("Enable Link Router", isOn: linkRouterBinding(\.isEnabled))
                HStack {
                    Label(
                        isDefaultBrowser
                            ? "Power Tools is the system link handler"
                            : "Power Tools is not the system link handler",
                        systemImage: isDefaultBrowser ? "checkmark.circle.fill" : "exclamationmark.triangle"
                    )
                    Spacer()
                    Button(isChangingDefaultBrowser ? "Waiting for macOS…" : "Make Default") {
                        makeDefaultBrowser()
                    }
                    .disabled(isDefaultBrowser || isChangingDefaultBrowser)
                }
            }

            Section("Browser Choices") {
                RouteTargetPicker(
                    title: "Primary browser",
                    selection: linkRouterBinding(\.primaryTarget)
                )
                Picker("Browser picker modifier", selection: linkRouterBinding(\.browserPickerModifier)) {
                    ForEach(BrowserPickerModifier.allCases) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                Label(
                    browserPickerHelpText,
                    systemImage: "rectangle.stack.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Test Routing") {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open an example link")
                            .font(.headline)
                        Text(
                            "Cleans an example.com URL with a tracking parameter, applies your rules, and opens it using the current settings."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Test Link") { routeTestLink() }
                        .accessibilityLabel("Open a test link")
                }
                .padding(.vertical, 2)
            }

            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: linkRouterBinding(\.showMenuBarIcon))
                Picker("Icon", selection: linkRouterBinding(\.menuBarIconStyle)) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { settingsStore.settings.linkRouter.launchAtLogin },
                        set: {
                            settingsStore.settings.linkRouter.launchAtLogin = $0
                            environment.linkRouterModule.configureLaunchAtLogin()
                        }
                    ))
            }

            Section("Setup Guide") {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("First-use guide")
                            .font(.headline)
                        Text("Review how system links, browser choices, and default-handler setup work.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run Guide Again") { WindowPresenter.shared.showOnboarding() }
                        .accessibilityLabel("Run first-use guide again")
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
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

    private var browserPickerHelpText: String {
        let modifier = settingsStore.settings.linkRouter.browserPickerModifier
        if modifier == .disabled {
            return "The browser-picker modifier is disabled. Rules can still open the picker for matching links."
        }
        return "Hold \(modifier.displayName) while opening a link to choose from every browser shown in the picker."
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
