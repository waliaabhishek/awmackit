import AppKit
import SwiftUI

struct RoutingLogView: View {
    @EnvironmentObject private var logger: RoutingLogger
    @State private var searchText = ""

    private var entries: [RoutingLogEntry] {
        guard !searchText.isEmpty else { return logger.entries }
        return logger.entries.filter {
            $0.stage.localizedCaseInsensitiveContains(searchText)
                || $0.message.localizedCaseInsensitiveContains(searchText)
                || $0.level.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Filter log", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                Spacer()
                Button("Copy Visible") { copyVisibleEntries() }
                    .disabled(entries.isEmpty)
                Button("Clear") { logger.clear() }
                    .disabled(logger.entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if entries.isEmpty {
                ContentUnavailableView(
                    "No Routing Log Entries",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Enable normal or verbose logging in Advanced settings, then route a link.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(entries) {
                    TableColumn("Time") { entry in
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("Level") { entry in
                        Label(entry.level.rawValue.capitalized, systemImage: symbol(for: entry.level))
                    }
                    .width(min: 85, ideal: 105)
                    TableColumn("Stage", value: \.stage)
                        .width(min: 90, ideal: 120)
                    TableColumn("Message") { entry in
                        Text(entry.message)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    .width(min: 320, ideal: 520)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func symbol(for level: RoutingLogEntry.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .debug: "ladybug"
        }
    }

    private func copyVisibleEntries() {
        let formatter = ISO8601DateFormatter()
        let text = entries.map {
            "\(formatter.string(from: $0.timestamp)) [\($0.level.rawValue.uppercased())] \($0.stage): \($0.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
