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

struct HistoryLoadIssue: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let fileURL: URL
}

enum HistoryStoreError: LocalizedError {
    case persistenceBlocked
    case entryTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .persistenceBlocked:
            "History cannot be changed until the existing file is backed up and reset."
        case .entryTooLarge(let byteCount):
            "A history entry requires \(byteCount) bytes, which exceeds the history storage limit."
        }
    }
}

private struct HistoryLoadSnapshot: Sendable {
    let entries: [LinkHistoryEntry]
    let recordCount: Int
    let requiresCompaction: Bool
}

private enum HistoryInitialLoadResult: Sendable {
    case success(HistoryLoadSnapshot)
    case failure(String)
}

private enum HistoryInitialLoadState {
    case loading(Task<HistoryInitialLoadResult, Never>)
    case loaded
}

@MainActor
final class HistoryStore: ObservableObject {
    static let defaultMaximumStorageBytes = 16 * 1_024 * 1_024

    @Published private(set) var entries: [LinkHistoryEntry] = []
    @Published private(set) var lastPersistenceError: String?
    @Published private(set) var loadIssue: HistoryLoadIssue?

    private let storageURL: URL
    private let maximumStorageBytes: Int
    private let writer: HistoryPersistenceWriter
    private var initialLoadState: HistoryInitialLoadState
    private var persistenceIsBlocked = true

    init(
        storageURL explicitURL: URL? = nil,
        maximumStorageBytes: Int = HistoryStore.defaultMaximumStorageBytes
    ) {
        let fileManager = FileManager.default
        let support =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let defaultDirectory = support.appendingPathComponent(
            AppIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )
        let resolvedURL = explicitURL ?? defaultDirectory.appendingPathComponent("link-history.json")
        let boundedMaximumStorageBytes = max(1, maximumStorageBytes)
        storageURL = resolvedURL
        self.maximumStorageBytes = boundedMaximumStorageBytes
        writer = HistoryPersistenceWriter(maximumStorageBytes: boundedMaximumStorageBytes)
        initialLoadState = .loading(
            Task.detached(priority: .utility) {
                do {
                    return .success(
                        try HistoryJournalCodec.load(
                            from: resolvedURL,
                            maximumBytes: boundedMaximumStorageBytes
                        ))
                } catch {
                    return .failure(error.localizedDescription)
                }
            })
    }

    func loadIfNeeded() async {
        guard case .loading(let task) = initialLoadState else { return }
        let result = await task.value
        guard case .loading = initialLoadState else { return }
        initialLoadState = .loaded

        switch result {
        case .success(let snapshot):
            entries = snapshot.entries
            persistenceIsBlocked = false
            await writer.configure(
                url: storageURL,
                recordCount: snapshot.recordCount,
                requiresCompaction: snapshot.requiresCompaction
            )
        case .failure(let message):
            loadIssue = HistoryLoadIssue(
                message: "PotliJi did not overwrite the unreadable history file. \(message)",
                fileURL: storageURL
            )
            lastPersistenceError = HistoryStoreError.persistenceBlocked.localizedDescription
        }
    }

    func append(_ entry: LinkHistoryEntry, limit: Int) async {
        await loadIfNeeded()
        guard !persistenceIsBlocked else { return }

        do {
            let byteCount = try HistoryJournalCodec.encodedLine(for: .append(entry)).count
            guard byteCount <= maximumStorageBytes else {
                lastPersistenceError = HistoryStoreError.entryTooLarge(byteCount).localizedDescription
                return
            }
        } catch {
            lastPersistenceError = error.localizedDescription
            return
        }

        entries.insert(entry, at: 0)
        let boundedLimit = min(max(1, limit), 5_000)
        let removedEntries: [LinkHistoryEntry]
        if entries.count > boundedLimit {
            removedEntries = Array(entries.suffix(from: boundedLimit))
            entries.removeLast(entries.count - boundedLimit)
        } else {
            removedEntries = []
        }

        var records: [HistoryJournalRecord] = [.append(entry)]
        if !removedEntries.isEmpty {
            records.append(.remove(removedEntries.map(\.id)))
        }
        await persist(records)
    }

    func clear() async {
        await loadIfNeeded()
        guard !persistenceIsBlocked else { return }
        entries.removeAll()
        await persist([.clear])
    }

    func delete(_ entry: LinkHistoryEntry) async {
        await loadIfNeeded()
        guard !persistenceIsBlocked else { return }
        entries.removeAll { $0.id == entry.id }
        await persist([.remove([entry.id])])
    }

    func flush() async throws {
        await loadIfNeeded()
        guard !persistenceIsBlocked else { throw HistoryStoreError.persistenceBlocked }
        try await writer.flush()
    }

    @discardableResult
    func backUpAndResetAfterLoadFailure() async throws -> URL? {
        await loadIfNeeded()
        guard persistenceIsBlocked else { return nil }

        let sourceURL = storageURL
        let backupURL = try await Task.detached(priority: .userInitiated) { () -> URL? in
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let candidate =
                sourceURL
                .deletingPathExtension()
                .appendingPathExtension("backup-\(timestamp).json")
            try FileManager.default.copyItem(at: sourceURL, to: candidate)
            return candidate
        }.value

        try await writer.reset(to: sourceURL)
        entries = []
        persistenceIsBlocked = false
        loadIssue = nil
        lastPersistenceError = nil
        return backupURL
    }

    private func persist(_ records: [HistoryJournalRecord]) async {
        do {
            entries = try await writer.record(records, currentEntries: entries, to: storageURL)
            lastPersistenceError = nil
        } catch {
            await writer.requireCompaction()
            lastPersistenceError = error.localizedDescription
        }
    }
}

private struct HistoryJournalRecord: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case append
        case remove
        case clear
    }

    let kind: Kind
    let entry: LinkHistoryEntry?
    let ids: [UUID]?

    static func append(_ entry: LinkHistoryEntry) -> HistoryJournalRecord {
        HistoryJournalRecord(kind: .append, entry: entry, ids: nil)
    }

    static func remove(_ ids: [UUID]) -> HistoryJournalRecord {
        HistoryJournalRecord(kind: .remove, entry: nil, ids: ids)
    }

    static let clear = HistoryJournalRecord(kind: .clear, entry: nil, ids: nil)
}

private enum HistoryJournalCodec {
    static func load(from url: URL, maximumBytes: Int) throws -> HistoryLoadSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return HistoryLoadSnapshot(entries: [], recordCount: 0, requiresCompaction: false)
        }
        let data = try BoundedFileReader.read(from: url, maximumBytes: maximumBytes)
        guard !data.isEmpty else {
            return HistoryLoadSnapshot(entries: [], recordCount: 0, requiresCompaction: false)
        }

        if data.first(where: { !$0.isASCIIWhitespace }) == 0x5B {
            let decoder = makeDecoder()
            let entries = try decoder.decode([LinkHistoryEntry].self, from: data)
            return HistoryLoadSnapshot(
                entries: Array(entries.prefix(5_000)),
                recordCount: entries.count,
                requiresCompaction: true
            )
        }

        let hasTrailingNewline = data.last == 0x0A
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        let decoder = makeDecoder()
        var values: [UUID: (sequence: Int, entry: LinkHistoryEntry)] = [:]
        var decodedRecordCount = 0
        var ignoredPartialRecord = false

        for (index, line) in lines.enumerated() {
            do {
                let record = try decoder.decode(HistoryJournalRecord.self, from: Data(line))
                decodedRecordCount += 1
                switch record.kind {
                case .append:
                    guard let entry = record.entry else { throw CocoaError(.coderInvalidValue) }
                    values[entry.id] = (decodedRecordCount, entry)
                case .remove:
                    guard let ids = record.ids else { throw CocoaError(.coderInvalidValue) }
                    for id in ids { values[id] = nil }
                case .clear:
                    values.removeAll()
                }
            } catch {
                let isRecoverableTrailingFragment = !hasTrailingNewline && index == lines.count - 1 && index > 0
                guard isRecoverableTrailingFragment else { throw error }
                ignoredPartialRecord = true
            }
        }

        let entries = values.values.sorted { $0.sequence > $1.sequence }.map(\.entry)
        return HistoryLoadSnapshot(
            entries: entries,
            recordCount: decodedRecordCount,
            requiresCompaction: ignoredPartialRecord
        )
    }

    static func encodedLine(for record: HistoryJournalRecord) throws -> Data {
        var data = try makeEncoder().encode(record)
        data.append(0x0A)
        return data
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private actor HistoryPersistenceWriter {
    private let maximumStorageBytes: Int
    private var configuredURL: URL?
    private var recordCount = 0
    private var requiresCompaction = false

    init(maximumStorageBytes: Int) {
        self.maximumStorageBytes = maximumStorageBytes
    }

    func configure(url: URL, recordCount: Int, requiresCompaction: Bool) {
        configuredURL = url
        self.recordCount = recordCount
        self.requiresCompaction = requiresCompaction
    }

    func record(
        _ records: [HistoryJournalRecord],
        currentEntries: [LinkHistoryEntry],
        to url: URL
    ) throws -> [LinkHistoryEntry] {
        try ensureConfigured(for: url)
        let encodedRecords = try records.map(HistoryJournalCodec.encodedLine(for:))
        let additionalBytes = encodedRecords.reduce(into: 0) { $0 += $1.count }
        let currentBytes = try fileSize(at: url)
        let compactionThreshold = max(1_000, currentEntries.count * 2)

        if requiresCompaction
            || currentBytes + additionalBytes > maximumStorageBytes
            || recordCount + records.count > compactionThreshold
        {
            return try replace(with: currentEntries, at: url)
        }

        try createParentDirectory(for: url)
        let payload = encodedRecords.reduce(into: Data()) { $0.append($1) }
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.synchronize()
        } else {
            try payload.write(to: url, options: .atomic)
        }
        recordCount += records.count
        return currentEntries
    }

    func reset(to url: URL) throws {
        try createParentDirectory(for: url)
        try Data().write(to: url, options: .atomic)
        configuredURL = url
        recordCount = 0
        requiresCompaction = false
    }

    func flush() throws {
        guard let configuredURL else { return }
        guard FileManager.default.fileExists(atPath: configuredURL.path) else { return }
        let handle = try FileHandle(forWritingTo: configuredURL)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func requireCompaction() {
        requiresCompaction = true
    }

    private func replace(with entries: [LinkHistoryEntry], at url: URL) throws -> [LinkHistoryEntry] {
        var retainedNewestFirst: [LinkHistoryEntry] = []
        var encodedNewestFirst: [Data] = []
        var byteCount = 0

        for entry in entries {
            let encoded = try HistoryJournalCodec.encodedLine(for: .append(entry))
            if retainedNewestFirst.isEmpty, encoded.count > maximumStorageBytes {
                throw HistoryStoreError.entryTooLarge(encoded.count)
            }
            guard byteCount + encoded.count <= maximumStorageBytes else { break }
            retainedNewestFirst.append(entry)
            encodedNewestFirst.append(encoded)
            byteCount += encoded.count
        }

        let payload = encodedNewestFirst.reversed().reduce(into: Data()) { $0.append($1) }
        try createParentDirectory(for: url)
        try payload.write(to: url, options: .atomic)
        configuredURL = url
        recordCount = retainedNewestFirst.count
        requiresCompaction = false
        return retainedNewestFirst
    }

    private func ensureConfigured(for url: URL) throws {
        guard configuredURL == url else {
            configuredURL = url
            recordCount = 0
            requiresCompaction = FileManager.default.fileExists(atPath: url.path)
            return
        }
    }

    private func createParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func fileSize(at url: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09
    }
}
