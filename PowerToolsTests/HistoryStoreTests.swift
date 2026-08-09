import LinkRouterCore
import XCTest

@testable import PowerTools

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testCorruptHistoryRemainsUntouchedUntilExplicitRecovery() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let original = Data("not-json".utf8)
        try original.write(to: historyURL)
        let store = HistoryStore(storageURL: historyURL)

        await store.loadIfNeeded()
        await store.append(makeEntry(index: 1), limit: 500)

        XCTAssertNotNil(store.loadIssue)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: historyURL), original)

        let recoveredURL = try await store.backUpAndResetAfterLoadFailure()
        let backupURL = try XCTUnwrap(recoveredURL)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
        XCTAssertEqual(try Data(contentsOf: historyURL), Data())
        XCTAssertNil(store.loadIssue)
    }

    func testLegacyArrayMigratesWithoutLosingEntries() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let originalEntries = [makeEntry(index: 2), makeEntry(index: 1)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(originalEntries).write(to: historyURL)
        let store = HistoryStore(storageURL: historyURL)

        await store.loadIfNeeded()
        await store.append(makeEntry(index: 3), limit: 500)
        let reloaded = HistoryStore(storageURL: historyURL)
        await reloaded.loadIfNeeded()

        XCTAssertEqual(reloaded.entries.map(\.id), [makeEntry(index: 3).id] + originalEntries.map(\.id))
        XCTAssertNil(reloaded.loadIssue)
    }

    func testAppendDeleteAndClearSurviveReload() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let first = makeEntry(index: 1)
        let second = makeEntry(index: 2)
        let store = HistoryStore(storageURL: historyURL)

        await store.append(first, limit: 500)
        await store.append(second, limit: 500)
        await store.delete(first)
        try await store.flush()

        let afterDelete = HistoryStore(storageURL: historyURL)
        await afterDelete.loadIfNeeded()
        XCTAssertEqual(afterDelete.entries.map(\.id), [second.id])

        await afterDelete.clear()
        let afterClear = HistoryStore(storageURL: historyURL)
        await afterClear.loadIfNeeded()
        XCTAssertTrue(afterClear.entries.isEmpty)
    }

    func testJournalCompactsBeforeExceedingByteLimit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let maximumBytes = 4 * 1_024
        let store = HistoryStore(storageURL: historyURL, maximumStorageBytes: maximumBytes)

        for index in 0..<12 {
            await store.append(makeEntry(index: index, queryBytes: 600), limit: 5_000)
        }
        try await store.flush()

        let fileSize = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: historyURL.path)[.size] as? NSNumber)?.intValue)
        XCTAssertLessThanOrEqual(fileSize, maximumBytes)
        XCTAssertLessThan(store.entries.count, 12)
        XCTAssertEqual(store.entries.first?.id, makeEntry(index: 11, queryBytes: 600).id)

        let reloaded = HistoryStore(storageURL: historyURL, maximumStorageBytes: maximumBytes)
        await reloaded.loadIfNeeded()
        XCTAssertEqual(reloaded.entries, store.entries)
    }

    func testCountLimitRemovesOldestEntriesFromJournal() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let store = HistoryStore(storageURL: historyURL)

        for index in 0..<5 {
            await store.append(makeEntry(index: index), limit: 3)
        }

        let reloaded = HistoryStore(storageURL: historyURL)
        await reloaded.loadIfNeeded()
        XCTAssertEqual(reloaded.entries.map(\.id), [4, 3, 2].map { makeEntry(index: $0).id })
    }

    func testOversizedEntryIsRejectedWithoutPoisoningLaterPersistence() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let store = HistoryStore(storageURL: historyURL, maximumStorageBytes: 1_024)

        await store.append(makeEntry(index: 1, queryBytes: 2_000), limit: 500)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.lastPersistenceError)

        let retained = makeEntry(index: 2)
        await store.append(retained, limit: 500)
        try await store.flush()

        let reloaded = HistoryStore(storageURL: historyURL, maximumStorageBytes: 1_024)
        await reloaded.loadIfNeeded()
        XCTAssertEqual(reloaded.entries, [retained])
    }

    private func makeEntry(index: Int, queryBytes: Int = 0) -> LinkHistoryEntry {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
        let suffix = queryBytes == 0 ? "" : "?value=\(String(repeating: "x", count: queryBytes))"
        let url = URL(string: "https://example.com/\(index)\(suffix)")!
        return LinkHistoryEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            originalURL: url,
            finalURL: url,
            sourceApplication: nil,
            target: .primary,
            matchedRuleName: nil,
            trigger: .manual
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PowerToolsHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
