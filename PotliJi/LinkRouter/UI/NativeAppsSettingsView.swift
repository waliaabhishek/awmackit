import AppKit
import LinkRouterCore
import SwiftUI

enum NativeAppPresentation {
    static func applicationURL(for definition: NativeAppDefinition) -> URL? {
        for bundleIdentifier in definition.candidateBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        if let scheme = definition.customScheme,
            let probe = URL(string: "\(scheme):"),
            let url = NSWorkspace.shared.urlForApplication(toOpen: probe)
        {
            return url
        }

        return nil
    }

    static func icon(for definition: NativeAppDefinition) -> NSImage {
        if let applicationURL = applicationURL(for: definition) {
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: definition.displayName) ?? NSImage()
    }
}

struct NativeAppsSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsPageHeader(
                    title: "App Links",
                    subtitle: "Choose which installed desktop apps should receive their supported links."
                )

                SettingsSectionCard("App Link Behavior") {
                    SettingsToggleRow(
                        title: "Open links in desktop apps",
                        detail:
                            "Custom rules are checked first. If an app is unavailable, normal browser routing is used.",
                        systemImage: "arrow.up.forward.app.fill",
                        isOn: linkRouterBinding(\.useNativeAppRouting)
                    )

                    if !installedDefinitions.isEmpty {
                        Divider()
                            .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
                        HStack {
                            Text("\(enabledInstalledCount) of \(installedDefinitions.count) detected apps enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Enable All Detected", action: enableAllDetected)
                            Button("Disable All", action: disableAllDetected)
                                .disabled(enabledInstalledCount == 0)
                        }
                    }
                }

                SettingsSectionCard("Apps on This Mac") {
                    if installedDefinitions.isEmpty {
                        ContentUnavailableView(
                            "No Supported Apps Detected",
                            systemImage: "app.dashed",
                            description: Text("Install a supported desktop app and return here to configure App Links.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(installedDefinitions.enumerated()), id: \.element.id) { index, definition in
                                appRow(definition)
                                if index + 1 < installedDefinitions.count {
                                    Divider()
                                        .padding(.leading, 48)
                                }
                            }
                        }
                    }
                }

                if !uninstalledDefinitions.isEmpty {
                    DisclosureGroup("Other supported apps (\(uninstalledDefinitions.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                "These become available automatically when PotliJi detects that they are installed."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(uninstalledDefinitions.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func appRow(_ definition: NativeAppDefinition) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NativeAppPresentation.icon(for: definition))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(definition.displayName)
                    .font(.headline)
                Text("Open supported \(definition.displayName) links in the app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Open in \(definition.displayName)", isOn: enabledBinding(definition.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!settingsStore.settings.linkRouter.useNativeAppRouting)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var installedDefinitions: [NativeAppDefinition] {
        NativeAppCatalog.builtIns.filter { NativeAppPresentation.applicationURL(for: $0) != nil }
    }

    private var uninstalledDefinitions: [NativeAppDefinition] {
        NativeAppCatalog.builtIns.filter { NativeAppPresentation.applicationURL(for: $0) == nil }
    }

    private var enabledInstalledCount: Int {
        let enabledIDs = settingsStore.settings.linkRouter.enabledNativeAppIDs
        return installedDefinitions.filter { enabledIDs.contains($0.id) }.count
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

    private func linkRouterBinding<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }

    private func enableAllDetected() {
        let ids = installedDefinitions.map(\.id)
        settingsStore.settings.linkRouter.enabledNativeAppIDs.formUnion(ids)
    }

    private func disableAllDetected() {
        let ids = Set(installedDefinitions.map(\.id))
        settingsStore.settings.linkRouter.enabledNativeAppIDs.subtract(ids)
    }
}
