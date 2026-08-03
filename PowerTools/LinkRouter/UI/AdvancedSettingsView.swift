import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var pendingError: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: "Advanced",
                subtitle: "Tune picker behavior, diagnostics, portability, and recovery options."
            )

            Form {
                if let issue = settingsStore.loadIssue {
                    Section("Settings Recovery") {
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        HStack {
                            Button("Reveal Original File") {
                                NSWorkspace.shared.activateFileViewerSelecting([issue.fileURL])
                            }
                            Button("Back Up and Reset…", role: .destructive) {
                                backUpAndResetSettings()
                            }
                        }
                    }
                }

                Section("Picker") {
                    SettingsToggleRow(
                        title: "Show the URL in the picker",
                        systemImage: "link",
                        isOn: setting(\.promptShowsURL)
                    )
                    SettingsToggleRow(
                        title: "Reveal Copy and Share while Option is held",
                        systemImage: "option",
                        isOn: setting(\.optionRevealsPromptActions)
                    )
                    SettingsToggleRow(
                        title: "Control opens the browser in the background",
                        systemImage: "control",
                        isOn: setting(\.openInBackgroundWhenControlHeld)
                    )
                    SettingsToggleRow(
                        title: "Remember picker position",
                        systemImage: "rectangle.and.hand.point.up.left",
                        isOn: setting(\.preservePromptPosition)
                    )
                    .help("The picker can be dragged by its background; its last position is restored across launches.")
                }

                Section("Browser Launching") {
                    SettingsToggleRow(
                        title: "Automate Safari private windows",
                        detail:
                            "Safari requires Accessibility permission because it does not expose private-window selection to third-party apps.",
                        systemImage: "hand.raised",
                        isOn: setting(\.safariPrivateUsesAccessibility)
                    )
                }

                Section("Diagnostics") {
                    SettingsControlRow(title: "Routing log", systemImage: "doc.text.magnifyingglass") {
                        Picker("Routing log", selection: setting(\.logLevel)) {
                            ForEach(RoutingLogLevel.allCases) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .settingsAccessoryPicker()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(environment.browserCatalog.allTargets.count) launch targets found")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Open Routing Log") { WindowPresenter.shared.showRoutingLog() }
                            Button("Refresh Browser Catalog") {
                                Task { await environment.browserCatalog.refresh() }
                            }
                        }
                    }
                }

                Section("Settings Portability") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("All settings") {
                            HStack {
                                Button("Export…") { exportSettings() }
                                Button("Import…") { importSettings() }
                            }
                        }
                        LabeledContent("Rules only") {
                            HStack {
                                Button("Export…") { exportRules() }
                                Button("Import…") { importRules() }
                            }
                        }
                    }
                    Text(
                        "Exports are human-readable JSON and include browser target identifiers, rules, cleaning preferences, and module configuration. History and diagnostic logs are not exported."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Reset") {
                    SettingsControlRow(
                        title: "Restore routing defaults",
                        detail: "Removes all rules and restores Link Router settings. History is kept.",
                        systemImage: "arrow.counterclockwise"
                    ) {
                        Button("Reset…", role: .destructive) {
                            let alert = NSAlert()
                            alert.messageText = "Reset Link Router Settings?"
                            alert.informativeText =
                                "This removes all rules and restores the default Link Router configuration. History is kept."
                            alert.addButton(withTitle: "Reset")
                            alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn {
                                settingsStore.settings.linkRouter = LinkRouterSettings()
                                environment.linkRouterModule.configureLaunchAtLogin()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            "Operation Failed",
            isPresented: Binding(
                get: { pendingError != nil },
                set: { if !$0 { pendingError = nil } }
            ),
            presenting: pendingError
        ) { _ in
            Button("OK") { pendingError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PowerTools-Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await settingsStore.exportAllSettings(to: url) } catch { pendingError = error }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await settingsStore.importAllSettings(from: url)
                environment.linkRouterModule.configureLaunchAtLogin()
            } catch {
                pendingError = error
            }
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PowerTools-Link-Rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await settingsStore.exportRules(to: url) } catch { pendingError = error }
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Import Link Rules"
        alert.informativeText = "Append imported rules or replace all existing rules?"
        alert.addButton(withTitle: "Append")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return }
        Task {
            do {
                try await settingsStore.importRules(
                    from: url,
                    replacingExisting: response == .alertSecondButtonReturn
                )
            } catch {
                pendingError = error
            }
        }
    }

    private func backUpAndResetSettings() {
        let alert = NSAlert()
        alert.messageText = "Back Up and Reset Settings?"
        alert.informativeText =
            "The original file will be copied beside settings.json before a clean settings file is created."
        alert.addButton(withTitle: "Back Up and Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                _ = try await settingsStore.backUpAndResetAfterLoadFailure()
                environment.linkRouterModule.configureLaunchAtLogin()
            } catch {
                pendingError = error
            }
        }
    }
}
