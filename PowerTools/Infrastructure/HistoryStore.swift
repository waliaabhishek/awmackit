import Combine
import Foundation
import LinkRouterCore

struct LinkHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var timestamp: Date
    var originalURL: URL
    var finalURL: URL
    var sourceApplication: SourceApplication?
    var target: RouteTarget
    var matchedRuleName: String?
    var trigger: RouterTrigger

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        originalURL: URL,
        finalURL: URL,
        sourceApplication: SourceApplication?,
        target: RouteTarget,
        matchedRuleName: String?,
        trigger: RouterTrigger
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalURL = originalURL
        self.finalURL = finalURL
        self.sourceApplication = sourceApplication
        self.target = target
        self.matchedRuleName = matchedRuleName
        self.trigger = trigger
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [LinkHistoryEntry] = []
    @Published private(set) var lastPersistenceError: String?

    private let storageURL: URL
    private let writer = HistoryPersistenceWriter()
    private var loadTask: Task<[LinkHistoryEntry], Never>?
    private var hasLoaded = false
    private var saveTask: Task<Void, Never>?

    init(storageURL explicitURL: URL? = nil) {
        let fileManager = FileManager.default
        let support =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let defaultDirectory = support.appendingPathComponent("PowerTools", isDirectory: true)
        let resolvedURL = explicitURL ?? defaultDirectory.appendingPathComponent("link-history.json")
        storageURL = resolvedURL
        loadTask = Task.detached(priority: .utility) {
            Self.load(from: resolvedURL)
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        let loaded = await loadTask?.value ?? []
        loadTask = nil
        hasLoaded = true
        entries = loaded
    }

    func append(_ entry: LinkHistoryEntry, limit: Int) async {
        await loadIfNeeded()
        entries.insert(entry, at: 0)
        if entries.count > max(1, limit) {
            entries.removeLast(entries.count - max(1, limit))
        }
        scheduleSave()
    }

    func clear() async {
        await loadIfNeeded()
        entries.removeAll()
        scheduleSave()
    }

    func delete(_ entry: LinkHistoryEntry) async {
        await loadIfNeeded()
        entries.removeAll { $0.id == entry.id }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = entries
        let url = storageURL
        let writer = writer
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await writer.write(snapshot, to: url)
                guard !Task.isCancelled else { return }
                self?.lastPersistenceError = nil
            } catch is CancellationError {
                return
            } catch {
                self?.lastPersistenceError = error.localizedDescription
            }
        }
    }

    private nonisolated static func load(from url: URL) -> [LinkHistoryEntry] {
        guard let data = try? BoundedFileReader.read(from: url, maximumBytes: 16 * 1_024 * 1_024) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LinkHistoryEntry].self, from: data)) ?? []
    }
}

private actor HistoryPersistenceWriter {
    func write(_ entries: [LinkHistoryEntry], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}
