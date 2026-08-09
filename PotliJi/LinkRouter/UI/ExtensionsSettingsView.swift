import AppKit
import SwiftUI

struct ExtensionsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: "Integrations",
                subtitle: "Use PotliJi from the Share menu, macOS Services, and URL commands."
            )

            Form {
                Section("Share Extension") {
                    SettingsActionRow(
                        title: "Share links with PotliJi",
                        detail: "Use Share → PotliJi Link Router from apps that expose the macOS Share menu.",
                        systemImage: "square.and.arrow.up",
                        buttonTitle: "Open Settings"
                    ) {
                        openSystemSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
                    }
                }

                Section("Services") {
                    SettingsActionRow(
                        title: "Open selected URLs",
                        detail: "Select text, then use Services → Open URLs with PotliJi or PotliJi Picker.",
                        systemImage: "text.magnifyingglass",
                        buttonTitle: "Keyboard Shortcuts"
                    ) {
                        openSystemSettings("x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")
                    }
                }

                Section("URL Commands") {
                    commandRow(
                        title: "Open through rules",
                        command: "potliji-link://open?url=https%3A%2F%2Fexample.com"
                    )
                    commandRow(
                        title: "Force the picker",
                        command: "potliji-link://open?prompt=1&url=https%3A%2F%2Fexample.com"
                    )
                    commandRow(
                        title: "Choose an application",
                        command: "potliji-link://open?app=com.google.Chrome&url=https%3A%2F%2Fexample.com"
                    )
                    commandRow(
                        title: "Clean and copy",
                        command: "potliji-link://clean?url=https%3A%2F%2Fexample.com%2F%3Futm_source%3Dtest"
                    )
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func commandRow(title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
