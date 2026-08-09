import Foundation

struct LegacyDataMigrationReport: Sendable {
    var migratedFiles: [String] = []
    var canonicalFilesPreserved: [String] = []
    var migratedPreferenceKeys: [String] = []
    var issues: [String] = []
}

enum LegacyDataMigrator {
    static let supportedFileNames = ["settings.json", "link-history.json"]

    static func migrate(
        fileManager: FileManager = .default,
        applicationSupportDirectory explicitSupportDirectory: URL? = nil,
        currentDefaults: UserDefaults = .standard,
        legacyDefaultsDomain explicitLegacyDefaultsDomain: [String: Any]? = nil
    ) -> LegacyDataMigrationReport {
        var report = LegacyDataMigrationReport()
        migrateApplicationSupport(
            fileManager: fileManager,
            applicationSupportDirectory: explicitSupportDirectory,
            report: &report
        )
        migratePreferences(
            currentDefaults: currentDefaults,
            legacyDefaultsDomain: explicitLegacyDefaultsDomain,
            report: &report
        )
        return report
    }

    private static func migrateApplicationSupport(
        fileManager: FileManager,
        applicationSupportDirectory explicitSupportDirectory: URL?,
        report: inout LegacyDataMigrationReport
    ) {
        let supportDirectory =
            explicitSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        let legacyDirectory = supportDirectory.appendingPathComponent(
            AppIdentity.LegacyCompatibility.applicationSupportDirectoryName,
            isDirectory: true
        )
        let canonicalDirectory = supportDirectory.appendingPathComponent(
            AppIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )

        var legacyIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: legacyDirectory.path, isDirectory: &legacyIsDirectory) else {
            return
        }
        guard legacyIsDirectory.boolValue else {
            report.issues.append("The legacy Application Support path is not a directory; it was left untouched.")
            return
        }

        do {
            try fileManager.createDirectory(at: canonicalDirectory, withIntermediateDirectories: true)
        } catch {
            report.issues.append(
                "Could not create the PotliJi Application Support directory: \(error.localizedDescription)"
            )
            return
        }

        for fileName in supportedFileNames {
            let sourceURL = legacyDirectory.appendingPathComponent(fileName)
            let destinationURL = canonicalDirectory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            if fileManager.fileExists(atPath: destinationURL.path) {
                report.canonicalFilesPreserved.append(fileName)
                continue
            }

            do {
                try copyAndVerify(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    fileManager: fileManager
                )
                report.migratedFiles.append(fileName)
            } catch {
                report.issues.append(
                    "Could not migrate \(fileName); the legacy file was left untouched. "
                        + error.localizedDescription
                )
            }
        }
    }

    private static func copyAndVerify(
        sourceURL: URL,
        destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent).legacy-migration-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        guard try filesMatch(sourceURL, temporaryURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        guard try filesMatch(sourceURL, destinationURL) else {
            try? fileManager.removeItem(at: destinationURL)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func filesMatch(_ firstURL: URL, _ secondURL: URL) throws -> Bool {
        let first = try FileHandle(forReadingFrom: firstURL)
        let second = try FileHandle(forReadingFrom: secondURL)
        defer {
            try? first.close()
            try? second.close()
        }

        while true {
            let firstChunk = try first.read(upToCount: 64 * 1_024) ?? Data()
            let secondChunk = try second.read(upToCount: 64 * 1_024) ?? Data()
            guard firstChunk == secondChunk else { return false }
            if firstChunk.isEmpty { return true }
        }
    }

    private static func migratePreferences(
        currentDefaults: UserDefaults,
        legacyDefaultsDomain explicitLegacyDefaultsDomain: [String: Any]?,
        report: inout LegacyDataMigrationReport
    ) {
        let legacyDefaultsDomain =
            explicitLegacyDefaultsDomain
            ?? currentDefaults.persistentDomain(
                forName: AppIdentity.LegacyCompatibility.bundleIdentifier
            )
            ?? [:]
        let mappings = [
            (
                AppIdentity.LegacyCompatibility.onboardingVersionKey,
                AppIdentity.onboardingVersionKey
            ),
            (
                AppIdentity.LegacyCompatibility.promptOriginKey,
                AppIdentity.promptOriginKey
            ),
            (
                AppIdentity.LegacyCompatibility.activeFocusTargetIDKey,
                AppIdentity.activeFocusTargetIDKey
            ),
            (AppIdentity.selectedSettingsPaneKey, AppIdentity.selectedSettingsPaneKey),
        ]

        for (legacyKey, canonicalKey) in mappings {
            guard currentDefaults.object(forKey: canonicalKey) == nil,
                let legacyValue = legacyDefaultsDomain[legacyKey]
            else { continue }
            currentDefaults.set(legacyValue, forKey: canonicalKey)
            if currentDefaults.object(forKey: canonicalKey) != nil {
                report.migratedPreferenceKeys.append(canonicalKey)
            } else {
                report.issues.append("Could not migrate the legacy preference for \(canonicalKey).")
            }
        }
    }
}
