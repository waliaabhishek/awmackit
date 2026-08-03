import AppKit
import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var historyStore: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: "Privacy",
                subtitle: "Control local link cleaning, redirect resolution, clipboard behavior, and history."
            )

            Form {
                Section("Link Cleaning") {
                    SettingsToggleRow(
                        title: "Remove known tracking parameters",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isOn: setting(\.removeTrackingParameters)
                    )
                    SettingsToggleRow(
                        title: "Unwrap embedded redirect links",
                        systemImage: "link",
                        isOn: setting(\.unwrapEmbeddedRedirects)
                    )
                    SettingsToggleRow(
                        title: "Expand recognized short links",
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        isOn: setting(\.expandShortURLs)
                    )
                    SettingsToggleRow(
                        title: "Resolve unknown redirect services",
                        detail:
                            "Uses a network request for unknown short-link hosts. Leave this off for strictly local processing.",
                        systemImage: "network",
                        isOn: setting(\.resolveUnknownRedirects)
                    )
                    SettingsToggleRow(
                        title: "Clean copied web links",
                        detail: "Removes configured tracking data when a web link is copied to the clipboard.",
                        systemImage: "clipboard",
                        isOn: Binding(
                            get: { settingsStore.settings.linkRouter.cleanCopiedLinks },
                            set: {
                                settingsStore.settings.linkRouter.cleanCopiedLinks = $0
                                environment.pasteboardMonitor.startIfNeeded()
                            }
                        )
                    )
                }

                Section("Tracking Parameter Overrides") {
                    LabeledContent("Also remove") {
                        MultilineListEditor(
                            values: setting(\.additionalTrackingParameters),
                            placeholder: "parameter_name\nanother_parameter"
                        )
                        .frame(height: 80)
                    }
                    LabeledContent("Never remove") {
                        MultilineListEditor(
                            values: setting(\.allowedTrackingParameters),
                            placeholder: "required_parameter"
                        )
                        .frame(height: 80)
                    }
                    Text("One query-parameter name per line. The allow list takes precedence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Short-Link Overrides") {
                    LabeledContent("Additional shortener hosts") {
                        MultilineListEditor(
                            values: setting(\.customShortenerHosts),
                            placeholder: "go.example.com\nlinks.example.org"
                        )
                        .frame(height: 80)
                    }
                }

                Section("Local History") {
                    SettingsToggleRow(
                        title: "Keep link history",
                        systemImage: "clock.arrow.circlepath",
                        isOn: setting(\.historyEnabled)
                    )
                    Stepper(
                        "Keep up to \(settingsStore.settings.linkRouter.historyLimit) entries",
                        value: setting(\.historyLimit),
                        in: 25...5_000,
                        step: 25
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(historyStore.entries.count) entries are currently stored on this Mac.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Open History") { WindowPresenter.shared.showHistory() }
                            Button("Clear History", role: .destructive) { Task { await historyStore.clear() } }
                                .disabled(historyStore.entries.isEmpty)
                        }
                    }
                }

                Section("Data Location") {
                    LabeledContent("Settings") {
                        Text(settingsStore.settingsURL.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Show Power Tools Data in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([settingsStore.settingsURL])
                    }
                    Text(
                        "Routing, cleaning, rules, and history run locally. Network access is used only when short-link expansion is enabled and a link needs resolution."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }
}

private struct MultilineListEditor: View {
    @Binding var values: [String]
    let placeholder: String

    private var text: Binding<String> {
        Binding(
            get: { values.joined(separator: "\n") },
            set: { newValue in
                values =
                    newValue
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
            if values.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    }
}
