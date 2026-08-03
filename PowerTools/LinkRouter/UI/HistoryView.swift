import AppKit
import LinkRouterCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var searchText = ""
    @State private var selection: LinkHistoryEntry.ID?

    private var filteredEntries: [LinkHistoryEntry] {
        guard !searchText.isEmpty else { return historyStore.entries }
        return historyStore.entries.filter { entry in
            [
                entry.originalURL.absoluteString,
                entry.finalURL.absoluteString,
                entry.sourceApplication?.name ?? "",
                entry.sourceApplication?.bundleIdentifier ?? "",
                entry.target.displayName,
                entry.matchedRuleName ?? "",
            ].contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search history", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                Spacer()
                Button("Clear", role: .destructive) { Task { await historyStore.clear() } }
                    .disabled(historyStore.entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Link History" : "No Matching Links",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        searchText.isEmpty
                            ? "Routed links appear here when history is enabled." : "Try a different search term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredEntries, selection: $selection) {
                    TableColumn("Time") { entry in
                        Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                            .monospacedDigit()
                    }
                    .width(min: 120, ideal: 145)

                    TableColumn("Link") { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.finalURL.host ?? entry.finalURL.absoluteString)
                                .fontWeight(.medium)
                            Text(entry.finalURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .contextMenu { contextMenu(for: entry) }
                    }
                    .width(min: 260, ideal: 420)

                    TableColumn("From") { entry in
                        Text(entry.sourceApplication?.name ?? "Unknown")
                    }
                    .width(min: 90, ideal: 130)

                    TableColumn("Opened In") { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.target.displayName)
                            if let rule = entry.matchedRuleName {
                                Text(rule).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 130, ideal: 190)
                }
                .contextMenu(forSelectionType: LinkHistoryEntry.ID.self) { ids in
                    if let id = ids.first, let entry = historyStore.entries.first(where: { $0.id == id }) {
                        contextMenu(for: entry)
                    }
                } primaryAction: { ids in
                    guard let id = ids.first,
                        let entry = historyStore.entries.first(where: { $0.id == id })
                    else { return }
                    open(entry, forcePrompt: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func contextMenu(for entry: LinkHistoryEntry) -> some View {
        Button("Open Again") { open(entry, forcePrompt: false) }
        Button("Open with Picker") { open(entry, forcePrompt: true) }
        Divider()
        Button("Copy Final URL") { copy(entry.finalURL) }
        if entry.originalURL != entry.finalURL {
            Button("Copy Original URL") { copy(entry.originalURL) }
        }
        Divider()
        Button("Delete Entry", role: .destructive) { Task { await historyStore.delete(entry) } }
    }

    private func open(_ entry: LinkHistoryEntry, forcePrompt: Bool) {
        let request = RouteRequest(urls: [entry.finalURL], trigger: .manual, forcePrompt: forcePrompt)
        Task { await environment.router.route(request) }
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}
