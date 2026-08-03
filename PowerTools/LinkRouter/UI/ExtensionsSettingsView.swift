import AppKit
import SwiftUI

struct ExtensionsSettingsView: View {
    var body: some View {
        Form {
            Section("Share Extension") {
                Label(
                    "Use Share → Power Tools Link Router from applications that expose the macOS Share menu.",
                    systemImage: "square.and.arrow.up")
                Button("Open Login Items & Extensions Settings") {
                    openSystemSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
                }
            }

            Section("Services") {
                Label(
                    "Select text in an application, then use Services → Open URLs with Power Tools or Open URLs with Power Tools Picker.",
                    systemImage: "text.magnifyingglass")
                Button("Open Keyboard Shortcuts for Services") {
                    openSystemSettings("x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")
                }
            }

            Section("URL Commands") {
                commandRow(
                    title: "Open through rules",
                    command: "powertools-link://open?url=https%3A%2F%2Fexample.com"
                )
                commandRow(
                    title: "Force the picker",
                    command: "powertools-link://open?prompt=1&url=https%3A%2F%2Fexample.com"
                )
                commandRow(
                    title: "Choose an application",
                    command: "powertools-link://open?app=com.google.Chrome&url=https%3A%2F%2Fexample.com"
                )
                commandRow(
                    title: "Clean and copy",
                    command: "powertools-link://clean?url=https%3A%2F%2Fexample.com%2F%3Futm_source%3Dtest"
                )
            }
        }
        .formStyle(.grouped)
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
