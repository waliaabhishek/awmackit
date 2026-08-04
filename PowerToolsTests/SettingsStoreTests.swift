import LinkRouterCore
import XCTest

@testable import PowerTools

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testCorruptSettingsRemainUntouchedUntilExplicitRecovery() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let original = Data("not-json".utf8)
        try original.write(to: settingsURL)

        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()
        XCTAssertNotNil(store.loadIssue)

        do {
            try await store.saveImmediately()
            XCTFail("A protected settings file must not be overwritten.")
        } catch SettingsStoreError.persistenceBlocked {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: settingsURL), original)

        let recoveredURL = try await store.backUpAndResetAfterLoadFailure()
        let backupURL = try XCTUnwrap(recoveredURL)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)))
    }

    func testNewerSchemaIsNotOverwrittenOnSave() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        var futureSettings = PowerToolsSettings()
        futureSettings.schemaVersion = PowerToolsSettings.currentSchemaVersion + 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(futureSettings)
        try original.write(to: settingsURL)

        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()
        XCTAssertNotNil(store.loadIssue)
        do {
            try await store.saveImmediately()
            XCTFail("A newer schema must remain write-protected.")
        } catch SettingsStoreError.persistenceBlocked {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: settingsURL), original)
    }

    func testSaveCreatesMissingParentDirectoryOffMainActor() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("nested/settings.json")
        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()
        store.settings.linkRouter.historyLimit = 321

        try await store.saveImmediately()

        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertEqual(store.settings.linkRouter.historyLimit, 321)
    }

    func testRedirectLimitDefaultsToTenWhenMissingFromStoredSettings() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let encodedDefaults = try JSONEncoder().encode(PowerToolsSettings())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedDefaults) as? [String: Any]
        )
        var linkRouter = try XCTUnwrap(object["linkRouter"] as? [String: Any])
        linkRouter["shortURLRedirectLimit"] = nil
        object["linkRouter"] = linkRouter
        try JSONSerialization.data(withJSONObject: object).write(to: settingsURL)

        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()

        XCTAssertNil(store.loadIssue)
        XCTAssertEqual(store.settings.linkRouter.shortURLRedirectLimit, 10)
    }

    func testRedirectLimitPersists() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()
        store.settings.linkRouter.shortURLRedirectLimit = 17
        try await store.saveImmediately()

        let reloadedStore = SettingsStore(settingsURL: settingsURL)
        await reloadedStore.loadIfNeeded()

        XCTAssertNil(reloadedStore.loadIssue)
        XCTAssertEqual(reloadedStore.settings.linkRouter.shortURLRedirectLimit, 17)
    }

    func testOversizedSettingsRemainWriteProtected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let original = Data(repeating: 0x20, count: RuleTransfer.maximumDocumentBytes + 1)
        try original.write(to: settingsURL)

        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()
        XCTAssertNotNil(store.loadIssue)
        do {
            try await store.saveImmediately()
            XCTFail("An oversized settings file must remain write-protected.")
        } catch SettingsStoreError.persistenceBlocked {
            // Expected.
        }
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: settingsURL.path)[.size] as? Int, original.count)
    }

    func testVersionOneAlternativeRulesMigrateToTheirConfiguredBrowser() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let configuredBrowser = RouteTarget(
            id: "browser.example",
            kind: .application,
            displayName: "Example Browser",
            bundleIdentifier: "com.example.browser"
        )
        var oldSettings = PowerToolsSettings()
        oldSettings.schemaVersion = 1
        oldSettings.linkRouter.alternativeTarget = configuredBrowser
        oldSettings.linkRouter.rules = [
            LinkRule(name: "Legacy alternative", target: .alternative)
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(oldSettings).write(to: settingsURL)

        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()

        XCTAssertNil(store.loadIssue)
        XCTAssertEqual(store.settings.schemaVersion, PowerToolsSettings.currentSchemaVersion)
        XCTAssertEqual(store.settings.linkRouter.rules.first?.target, configuredBrowser)
    }

    func testVersionTwoRulesMigrateToAdvancedConditionGroups() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        var oldSettings = PowerToolsSettings()
        oldSettings.schemaVersion = 2
        oldSettings.linkRouter.rules = [
            LinkRule(
                name: "Legacy YouTube rule",
                urlMatchers: [
                    URLMatcher(kind: .hostSuffix, pattern: "youtube.com"),
                    URLMatcher(kind: .pathPrefix, pattern: "/watch"),
                ],
                target: .primary
            )
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(oldSettings).write(to: settingsURL)

        let store = SettingsStore(settingsURL: settingsURL)
        await store.loadIfNeeded()

        let migrated = try XCTUnwrap(store.settings.linkRouter.rules.first)
        XCTAssertNil(store.loadIssue)
        XCTAssertEqual(store.settings.schemaVersion, PowerToolsSettings.currentSchemaVersion)
        XCTAssertEqual(migrated.editorKind, .advanced)
        XCTAssertEqual(migrated.urlMatcherGroups?.count, 1)
        XCTAssertEqual(migrated.urlMatcherGroups?.first?.mode, .all)
        XCTAssertEqual(migrated.urlMatcherGroups?.first?.matchers.map(\.pattern), ["youtube.com", "/watch"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PowerToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
