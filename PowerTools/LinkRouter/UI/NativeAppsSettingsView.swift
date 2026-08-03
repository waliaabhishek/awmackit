import AppKit
import LinkRouterCore
import SwiftUI
import UniformTypeIdentifiers

struct NativeAppsSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var browserCatalog: BrowserCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apps and Web Services").font(.title2.bold())
            Text(
                "Open supported web links directly in installed desktop apps or a browser/PWA chosen for the service. User rules take precedence."
            )
            .foregroundStyle(.secondary)

            GroupBox("Services Without a Dedicated Desktop App") {
                VStack(alignment: .leading, spacing: 10) {
                    serviceTargetPicker(
                        title: "Google Meet",
                        selection: googleMeetSelection,
                        automaticTitle: "Automatic Chromium browser",
                        configuredTarget: settingsStore.settings.linkRouter.googleMeetTarget,
                        chooseApplication: chooseGoogleMeetApplication
                    )
                    Text(
                        "Automatic mode prefers Chrome, then Edge, Brave, Vivaldi, Chromium, and other supported Chromium browsers."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    serviceTargetPicker(
                        title: "YouTube",
                        selection: youtubeSelection,
                        automaticTitle: nil,
                        configuredTarget: settingsStore.settings.linkRouter.youtubeTarget,
                        chooseApplication: chooseYouTubeApplication
                    )
                }
                .padding(.vertical, 4)
            }

            Toggle(
                "Enable native app routing",
                isOn: Binding(
                    get: { settingsStore.settings.linkRouter.useNativeAppRouting },
                    set: { settingsStore.settings.linkRouter.useNativeAppRouting = $0 }
                ))

            List(NativeAppCatalog.builtIns) { definition in
                HStack {
                    Toggle(isOn: enabledBinding(definition.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.displayName)
                            Text(definition.hostSuffixes.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if installed(definition) {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func serviceTargetPicker(
        title: String,
        selection: Binding<String>,
        automaticTitle: String?,
        configuredTarget: RouteTarget?,
        chooseApplication: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker(title, selection: selection) {
                Text("Disabled").tag("__disabled__")
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
            HStack {
                Text("Not listed above?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose Another Application…", action: chooseApplication)
            }
        }
        .padding(.vertical, 3)
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

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings.linkRouter.enabledNativeAppIDs.contains(id) },
            set: { enabled in
                if enabled {
                    settingsStore.settings.linkRouter.enabledNativeAppIDs.insert(id)
                } else {
                    settingsStore.settings.linkRouter.enabledNativeAppIDs.remove(id)
                }
            }
        )
    }

    private func installed(_ definition: NativeAppDefinition) -> Bool {
        definition.candidateBundleIdentifiers.contains {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
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
