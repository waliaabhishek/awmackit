import AppKit
import LinkRouterCore
import SwiftUI
import UniformTypeIdentifiers

struct RoutingSettingsView: View {
    private enum Page {
        case overview
        case appLinks
        case rules
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var browserCatalog: BrowserCatalog
    @State private var page: Page = .overview

    @ViewBuilder
    var body: some View {
        switch page {
        case .overview:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsPageHeader(
                        title: "Routing",
                        subtitle: "Choose where links normally open, then add rules only when you need exceptions."
                    )

                    defaultDestinationCard
                    appLinksCard
                    webServicesCard
                    rulesCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .appLinks:
            detailPage {
                NativeAppsSettingsView()
            }
        case .rules:
            detailPage {
                RulesSettingsView()
            }
        }
    }

    private func detailPage<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    page = .overview
                } label: {
                    Label("Back to Routing", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                content()
                    .frame(width: geometry.size.width)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private var defaultDestinationCard: some View {
        SettingsSectionCard("Default Destination") {
            SettingsControlRow(
                title: "Primary browser",
                systemImage: "safari"
            ) {
                RouteTargetPicker(
                    title: "Primary browser",
                    selection: linkRouterBinding(\.primaryTarget)
                )
                .settingsAccessoryPicker()
            }

            Divider()
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)

            SettingsControlRow(
                title: "Browser picker shortcut",
                systemImage: "keyboard"
            ) {
                Picker(
                    "Browser picker shortcut",
                    selection: linkRouterBinding(\.browserPickerModifier)
                ) {
                    ForEach(BrowserPickerModifier.allCases) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                .settingsAccessoryPicker()
            }

            Label(browserPickerHelpText, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
        }
    }

    private var appLinksCard: some View {
        SettingsSectionCard("App Links") {
            SettingsToggleRow(
                title: "Open links in desktop apps",
                detail: "Use enabled apps installed on this Mac. Custom rules still take priority.",
                systemImage: "arrow.up.forward.app.fill",
                isOn: linkRouterBinding(\.useNativeAppRouting)
            )

            Divider()
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)

            HStack(spacing: 12) {
                Text(appLinksSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Customize…") { page = .appLinks }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var webServicesCard: some View {
        SettingsSectionCard("Web Service Destinations") {
            serviceDestinationRow(
                title: "Google Meet",
                detail: "Choose a Chromium browser or profile for meeting links.",
                systemImage: "video.fill",
                selection: googleMeetSelection,
                automaticTitle: "Automatic Chromium Browser",
                configuredTarget: settingsStore.settings.linkRouter.googleMeetTarget,
                chooseApplication: chooseGoogleMeetApplication
            )

            Divider()
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)

            serviceDestinationRow(
                title: "YouTube",
                detail: "Choose a browser, profile, or PWA for video links.",
                systemImage: "play.rectangle.fill",
                selection: youtubeSelection,
                automaticTitle: nil,
                configuredTarget: settingsStore.settings.linkRouter.youtubeTarget,
                chooseApplication: chooseYouTubeApplication
            )
        }
    }

    private var rulesCard: some View {
        SettingsSectionCard("Rules & Exceptions") {
            SettingsControlRow(
                title: rulesSummary,
                detail: "Rules are checked first and can override every default destination above.",
                systemImage: "wand.and.stars"
            ) {
                Button(settingsStore.settings.linkRouter.rules.isEmpty ? "Add Rule…" : "Manage…") {
                    page = .rules
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func serviceDestinationRow(
        title: String,
        detail: String,
        systemImage: String,
        selection: Binding<String>,
        automaticTitle: String?,
        configuredTarget: RouteTarget?,
        chooseApplication: @escaping () -> Void
    ) -> some View {
        SettingsControlRow(
            title: title,
            detail: detail,
            systemImage: systemImage
        ) {
            HStack(spacing: 8) {
                Picker(title, selection: selection) {
                    Text("Use Normal Routing").tag("__disabled__")
                    if let automaticTitle {
                        Text(automaticTitle).tag("__automatic__")
                    }
                    Divider()
                    if let configuredTarget,
                        !browserCatalog.normalTargets.contains(where: { $0.id == configuredTarget.id })
                    {
                        Text(configuredTarget.displayName).tag(configuredTarget.id)
                        Divider()
                    }
                    ForEach(browserCatalog.normalTargets) { target in
                        Label {
                            Text(target.displayName)
                        } icon: {
                            Image(nsImage: browserCatalog.icon(for: target))
                        }
                        .tag(target.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Menu {
                    Button("Choose Another Application…", action: chooseApplication)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Choose another application for \(title)")
            }
        }
    }

    private var installedDefinitions: [NativeAppDefinition] {
        NativeAppCatalog.builtIns.filter { NativeAppPresentation.applicationURL(for: $0) != nil }
    }

    private var enabledInstalledDefinitions: [NativeAppDefinition] {
        let enabledIDs = settingsStore.settings.linkRouter.enabledNativeAppIDs
        return installedDefinitions.filter { enabledIDs.contains($0.id) }
    }

    private var appLinksSummary: String {
        guard settingsStore.settings.linkRouter.useNativeAppRouting else {
            return "Off · \(installedDefinitions.count) supported apps detected"
        }
        guard !enabledInstalledDefinitions.isEmpty else {
            return "No detected apps are enabled"
        }
        let names = enabledInstalledDefinitions.prefix(3).map(\.displayName)
        let remainder = enabledInstalledDefinitions.count - names.count
        if remainder > 0 {
            return "Opening links in \(names.joined(separator: ", ")) and \(remainder) more"
        }
        return "Opening links in \(names.joined(separator: ", "))"
    }

    private var rulesSummary: String {
        let rules = settingsStore.settings.linkRouter.rules
        let enabledCount = rules.filter(\.isEnabled).count
        guard !rules.isEmpty else { return "No custom rules" }
        return "\(enabledCount) of \(rules.count) custom rules enabled"
    }

    private var browserPickerHelpText: String {
        let modifier = settingsStore.settings.linkRouter.browserPickerModifier
        if modifier == .disabled {
            return "The browser-picker shortcut is off. A rule can still show the picker for selected links."
        }
        return "Hold \(modifier.displayName) while opening a link to choose from browsers shown in the picker."
    }

    private var googleMeetSelection: Binding<String> {
        Binding(
            get: {
                let settings = settingsStore.settings.linkRouter
                guard settings.googleMeetRoutingEnabled else { return "__disabled__" }
                return settings.googleMeetTarget?.id ?? "__automatic__"
            },
            set: { value in
                switch value {
                case "__disabled__":
                    settingsStore.settings.linkRouter.googleMeetRoutingEnabled = false
                    settingsStore.settings.linkRouter.googleMeetTarget = nil
                case "__automatic__":
                    settingsStore.settings.linkRouter.googleMeetRoutingEnabled = true
                    settingsStore.settings.linkRouter.googleMeetTarget = nil
                default:
                    settingsStore.settings.linkRouter.googleMeetRoutingEnabled = true
                    settingsStore.settings.linkRouter.googleMeetTarget = browserCatalog.target(withID: value)
                }
            }
        )
    }

    private var youtubeSelection: Binding<String> {
        Binding(
            get: {
                let settings = settingsStore.settings.linkRouter
                guard settings.youtubeRoutingEnabled else { return "__disabled__" }
                return settings.youtubeTarget?.id ?? "__disabled__"
            },
            set: { value in
                if value == "__disabled__" {
                    settingsStore.settings.linkRouter.youtubeRoutingEnabled = false
                    settingsStore.settings.linkRouter.youtubeTarget = nil
                } else {
                    settingsStore.settings.linkRouter.youtubeRoutingEnabled = true
                    settingsStore.settings.linkRouter.youtubeTarget = browserCatalog.target(withID: value)
                }
            }
        )
    }

    private func linkRouterBinding<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }

    private func chooseGoogleMeetApplication() {
        guard let target = chooseApplicationTarget(serviceID: "google-meet") else { return }
        settingsStore.settings.linkRouter.googleMeetRoutingEnabled = true
        settingsStore.settings.linkRouter.googleMeetTarget = target
    }

    private func chooseYouTubeApplication() {
        guard let target = chooseApplicationTarget(serviceID: "youtube") else { return }
        settingsStore.settings.linkRouter.youtubeRoutingEnabled = true
        settingsStore.settings.linkRouter.youtubeTarget = target
    }

    private func chooseApplicationTarget(serviceID: String) -> RouteTarget? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let appURL = panel.url else { return nil }

        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        return RouteTarget(
            id: "service.\(serviceID).\(bundleIdentifier ?? appURL.path)",
            kind: .application,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            applicationPath: appURL.path
        )
    }
}
