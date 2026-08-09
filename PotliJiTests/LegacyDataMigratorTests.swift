import LinkRouterCore
import XCTest

@testable import PotliJi

@MainActor
final class LegacyDataMigratorTests: XCTestCase {
    func testOldOnlySupportDirectoryMigratesSettingsAndHistoryWithoutDeletingLegacyData() async throws {
        let supportDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let legacyDirectory = supportDirectory.appendingPathComponent(
            AppIdentity.LegacyCompatibility.applicationSupportDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        var settings = PotliJiSettings()
        settings.linkRouter.historyLimit = 237
        let settingsData = try JSONEncoder().encode(settings)
        let settingsURL = legacyDirectory.appendingPathComponent("settings.json")
        try settingsData.write(to: settingsURL)

        let historyEntry = makeHistoryEntry()
        let historyData = try JSONEncoder.withISO8601Dates.encode([historyEntry])
        let historyURL = legacyDirectory.appendingPathComponent("link-history.json")
        try historyData.write(to: historyURL)
        let unsupportedURL = legacyDirectory.appendingPathComponent("future-module.data")
        try Data("preserve me".utf8).write(to: unsupportedURL)

        let report = LegacyDataMigrator.migrate(
            applicationSupportDirectory: supportDirectory,
            currentDefaults: isolatedDefaults(),
            legacyDefaultsDomain: [:]
        )
        let canonicalDirectory = supportDirectory.appendingPathComponent(
            AppIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )

        XCTAssertEqual(Set(report.migratedFiles), Set(LegacyDataMigrator.supportedFileNames))
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: canonicalDirectory.appendingPathComponent("settings.json")),
            settingsData
        )
        XCTAssertEqual(
            try Data(contentsOf: canonicalDirectory.appendingPathComponent("link-history.json")),
            historyData
        )
        XCTAssertEqual(try Data(contentsOf: settingsURL), settingsData)
        XCTAssertEqual(try Data(contentsOf: historyURL), historyData)
        XCTAssertEqual(try Data(contentsOf: unsupportedURL), Data("preserve me".utf8))

        let settingsStore = SettingsStore(
            settingsURL: canonicalDirectory.appendingPathComponent("settings.json")
        )
        await settingsStore.loadIfNeeded()
        XCTAssertEqual(settingsStore.settings.linkRouter.historyLimit, 237)

        let historyStore = HistoryStore(
            storageURL: canonicalDirectory.appendingPathComponent("link-history.json")
        )
        await historyStore.loadIfNeeded()
        XCTAssertEqual(historyStore.entries, [historyEntry])
    }

    func testBothDirectoriesPreserveCanonicalFilesAndFillOnlyMissingSupportedFiles() throws {
        let supportDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let legacyDirectory = supportDirectory.appendingPathComponent(
            AppIdentity.LegacyCompatibility.applicationSupportDirectoryName,
            isDirectory: true
        )
        let canonicalDirectory = supportDirectory.appendingPathComponent(
            AppIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonicalDirectory, withIntermediateDirectories: true)

        let oldSettings = Data("old settings".utf8)
        let canonicalSettings = Data("canonical settings".utf8)
        let oldHistory = Data("old history".utf8)
        try oldSettings.write(to: legacyDirectory.appendingPathComponent("settings.json"))
        try oldHistory.write(to: legacyDirectory.appendingPathComponent("link-history.json"))
        try canonicalSettings.write(to: canonicalDirectory.appendingPathComponent("settings.json"))

        let firstReport = LegacyDataMigrator.migrate(
            applicationSupportDirectory: supportDirectory,
            currentDefaults: isolatedDefaults(),
            legacyDefaultsDomain: [:]
        )
        XCTAssertEqual(firstReport.canonicalFilesPreserved, ["settings.json"])
        XCTAssertEqual(firstReport.migratedFiles, ["link-history.json"])
        XCTAssertEqual(
            try Data(contentsOf: canonicalDirectory.appendingPathComponent("settings.json")),
            canonicalSettings
        )
        XCTAssertEqual(
            try Data(contentsOf: canonicalDirectory.appendingPathComponent("link-history.json")),
            oldHistory
        )

        let secondReport = LegacyDataMigrator.migrate(
            applicationSupportDirectory: supportDirectory,
            currentDefaults: isolatedDefaults(),
            legacyDefaultsDomain: [:]
        )
        XCTAssertTrue(secondReport.migratedFiles.isEmpty)
        XCTAssertEqual(
            Set(secondReport.canonicalFilesPreserved),
            Set(LegacyDataMigrator.supportedFileNames)
        )
    }

    func testUnsupportedLegacyFileTypeIsLeftUntouchedAndReported() throws {
        let supportDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let legacyDirectory = supportDirectory.appendingPathComponent(
            AppIdentity.LegacyCompatibility.applicationSupportDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let targetURL = supportDirectory.appendingPathComponent("outside.json")
        try Data("outside".utf8).write(to: targetURL)
        let symlinkURL = legacyDirectory.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        let report = LegacyDataMigrator.migrate(
            applicationSupportDirectory: supportDirectory,
            currentDefaults: isolatedDefaults(),
            legacyDefaultsDomain: [:]
        )

        XCTAssertTrue(report.migratedFiles.isEmpty)
        XCTAssertEqual(report.issues.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkURL.path))
        XCTAssertEqual(try Data(contentsOf: targetURL), Data("outside".utf8))
    }

    func testLegacyPreferencesMigrateWithoutOverwritingCanonicalValues() throws {
        let defaults = isolatedDefaults()
        let supportDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        defaults.set(9, forKey: AppIdentity.onboardingVersionKey)
        let legacyDomain: [String: Any] = [
            AppIdentity.LegacyCompatibility.onboardingVersionKey: 1,
            AppIdentity.LegacyCompatibility.promptOriginKey: ["x": 12.0, "y": 24.0],
            AppIdentity.LegacyCompatibility.activeFocusTargetIDKey: "browser.example",
            AppIdentity.selectedSettingsPaneKey: "extensions",
        ]

        let report = LegacyDataMigrator.migrate(
            applicationSupportDirectory: supportDirectory,
            currentDefaults: defaults,
            legacyDefaultsDomain: legacyDomain
        )

        XCTAssertEqual(defaults.integer(forKey: AppIdentity.onboardingVersionKey), 9)
        let promptOrigin = try XCTUnwrap(defaults.dictionary(forKey: AppIdentity.promptOriginKey))
        XCTAssertEqual(promptOrigin["x"] as? Double, 12.0)
        XCTAssertEqual(promptOrigin["y"] as? Double, 24.0)
        XCTAssertEqual(
            defaults.string(forKey: AppIdentity.activeFocusTargetIDKey),
            "browser.example"
        )
        XCTAssertEqual(defaults.string(forKey: AppIdentity.selectedSettingsPaneKey), "extensions")
        XCTAssertFalse(report.migratedPreferenceKeys.contains(AppIdentity.onboardingVersionKey))
        XCTAssertEqual(report.migratedPreferenceKeys.count, 3)
    }

    func testMigratedOnboardingStateStillRequiresOneTimePotliJiHandlerSetup() throws {
        let defaults = isolatedDefaults()
        let supportDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        _ = LegacyDataMigrator.migrate(
            applicationSupportDirectory: supportDirectory,
            currentDefaults: defaults,
            legacyDefaultsDomain: [
                AppIdentity.LegacyCompatibility.onboardingVersionKey: 1
            ]
        )

        let migratedVersion = defaults.integer(forKey: AppIdentity.onboardingVersionKey)
        XCTAssertEqual(migratedVersion, 1)
        XCTAssertLessThan(migratedVersion, WindowPresenter.currentOnboardingVersion)
    }

    private func makeHistoryEntry() -> LinkHistoryEntry {
        let url = URL(string: "https://example.com/migrated")!
        return LinkHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            timestamp: Date(timeIntervalSince1970: 42),
            originalURL: url,
            finalURL: url,
            sourceApplication: nil,
            target: .prompt,
            matchedRuleName: nil,
            trigger: .manual
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PotliJiMigrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "com.abhi.PotliJi.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private extension JSONEncoder {
    static var withISO8601Dates: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
