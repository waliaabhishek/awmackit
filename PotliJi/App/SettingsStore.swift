import Combine
import Foundation
import LinkRouterCore

struct SettingsLoadIssue: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let fileURL: URL
}

enum SettingsStoreError: LocalizedError {
    case unsupportedSchema(Int)
    case persistenceBlocked
    case settingsFileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "The settings file uses unsupported schema version \(version)."
        case .persistenceBlocked:
            "Settings cannot be saved until the existing file is backed up and reset or replaced by an import."
        case .settingsFileTooLarge(let byteCount):
            "The settings file is \(byteCount) bytes; the maximum is 16 MB."
        }
    }
}

private enum SettingsInitialLoadResult: Sendable {
    case success(PotliJiSettings)
    case failure(String)
}

private enum SettingsInitialLoadState {
    case loading(Task<SettingsInitialLoadResult, Never>)
    case loaded
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: PotliJiSettings {
        didSet { scheduleSave() }
    }

    @Published private(set) var loadIssue: SettingsLoadIssue?
    @Published private(set) var lastSaveErrorMessage: String?

    let settingsURL: URL

    private let writer = SettingsPersistenceWriter()
    private var saveTask: Task<Void, Never>?
    private var persistenceIsBlocked: Bool
    private var initialLoadState: SettingsInitialLoadState

    init(fileManager: FileManager = .default, settingsURL explicitURL: URL? = nil) {
        let applicationSupport =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let defaultDirectory = applicationSupport.appendingPathComponent(
            AppIdentity.applicationSupportDirectoryName,
            isDirectory: true
        )
        let resolvedURL = explicitURL ?? defaultDirectory.appendingPathComponent("settings.json")
        settingsURL = resolvedURL
        settings = PotliJiSettings()
        loadIssue = nil
        persistenceIsBlocked = true
        lastSaveErrorMessage = nil
        initialLoadState = .loading(
            Task.detached(priority: .userInitiated) {
                do {
                    return .success(try Self.load(from: resolvedURL) ?? PotliJiSettings())
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
        case .success(let loadedSettings):
            // Keep persistence blocked while publishing the initial value so `didSet`
            // cannot rewrite the file merely because startup completed.
            settings = loadedSettings
            persistenceIsBlocked = false
        case .failure(let message):
            loadIssue = SettingsLoadIssue(
                message: "PotliJi did not overwrite the unreadable settings file. \(message)",
                fileURL: settingsURL
            )
        }
    }

    func saveImmediately() async throws {
        await loadIfNeeded()
        guard !persistenceIsBlocked else { throw SettingsStoreError.persistenceBlocked }
        saveTask?.cancel()
        try await writer.write(settings, to: settingsURL)
        lastSaveErrorMessage = nil
    }

    func importAllSettings(from url: URL) async throws {
        await loadIfNeeded()
        let imported = try await Task.detached(priority: .userInitiated) {
            let data = try BoundedFileReader.read(from: url, maximumBytes: RuleTransfer.maximumDocumentBytes)
            return try Self.decodeSettings(from: data)
        }.value

        saveTask?.cancel()
        try await writer.write(imported, to: settingsURL)
        settings = imported
        persistenceIsBlocked = false
        loadIssue = nil
        lastSaveErrorMessage = nil
    }

    func exportAllSettings(to url: URL) async throws {
        await loadIfNeeded()
        try await writer.write(settings, to: url)
    }

    func importRules(from url: URL, replacingExisting: Bool) async throws {
        await loadIfNeeded()
        let imported = try await Task.detached(priority: .userInitiated) {
            let data = try BoundedFileReader.read(from: url, maximumBytes: RuleTransfer.maximumDocumentBytes)
            return try RuleTransfer().decode(data)
        }.value
        let migrated = Self.migratingRulesToCurrentModel(imported)
        if replacingExisting {
            settings.linkRouter.rules = migrated
        } else {
            let existingIDs = Set(settings.linkRouter.rules.map(\.id))
            settings.linkRouter.rules.append(contentsOf: migrated.filter { !existingIDs.contains($0.id) })
        }
    }

    func exportRules(to url: URL) async throws {
        await loadIfNeeded()
        let rules = settings.linkRouter.rules
        try await Task.detached(priority: .userInitiated) {
            try RuleTransfer().encode(rules).write(to: url, options: .atomic)
        }.value
    }

    @discardableResult
    func backUpAndResetAfterLoadFailure() async throws -> URL? {
        await loadIfNeeded()
        guard persistenceIsBlocked else { return nil }
        saveTask?.cancel()

        let sourceURL = settingsURL
        let backupURL = try await Task.detached(priority: .userInitiated) { () -> URL? in
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let candidate =
                sourceURL
                .deletingPathExtension()
                .appendingPathExtension("backup-\(timestamp).json")
            do {
                try FileManager.default.copyItem(at: sourceURL, to: candidate)
                return candidate
            } catch {
                throw error
            }
        }.value

        let defaults = PotliJiSettings()
        try await writer.write(defaults, to: sourceURL)
        settings = defaults
        persistenceIsBlocked = false
        loadIssue = nil
        lastSaveErrorMessage = nil
        return backupURL
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard !persistenceIsBlocked else { return }

        let snapshot = settings
        let url = settingsURL
        let writer = writer
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                try await writer.write(snapshot, to: url)
                guard !Task.isCancelled else { return }
                self?.lastSaveErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                self?.lastSaveErrorMessage = error.localizedDescription
            }
        }
    }

    private nonisolated static func load(from url: URL) throws -> PotliJiSettings? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try BoundedFileReader.read(from: url, maximumBytes: RuleTransfer.maximumDocumentBytes)
        return try decodeSettings(from: data)
    }

    private nonisolated static func decodeSettings(from data: Data) throws -> PotliJiSettings {
        guard data.count <= RuleTransfer.maximumDocumentBytes else {
            throw SettingsStoreError.settingsFileTooLarge(data.count)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let defaultsData = try encoder.encode(PotliJiSettings())

        let defaultsObject = try JSONSerialization.jsonObject(with: defaultsData)
        let storedObject = try JSONSerialization.jsonObject(with: data)
        let mergedObject = merge(defaults: defaultsObject, stored: storedObject)
        let mergedData = try JSONSerialization.data(withJSONObject: mergedObject)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PotliJiSettings.self, from: mergedData)
        guard decoded.schemaVersion <= PotliJiSettings.currentSchemaVersion else {
            throw SettingsStoreError.unsupportedSchema(decoded.schemaVersion)
        }
        var current = decoded
        if decoded.schemaVersion < 2 {
            let replacement = legacyAlternativeReplacement(in: current.linkRouter)
            current.linkRouter.rules = replacingLegacyAlternativeTargets(
                in: current.linkRouter.rules,
                with: replacement
            )
            if current.linkRouter.primaryTarget.kind == .alternativeBrowser {
                current.linkRouter.primaryTarget = replacement
            }
            if current.linkRouter.googleMeetTarget?.kind == .alternativeBrowser {
                current.linkRouter.googleMeetTarget = replacement
            }
            if current.linkRouter.youtubeTarget?.kind == .alternativeBrowser {
                current.linkRouter.youtubeTarget = replacement
            }
        }
        if decoded.schemaVersion < 3 {
            current.linkRouter.rules = migratingRulesToCurrentModel(current.linkRouter.rules)
        }
        if decoded.schemaVersion < 4 {
            current.linkRouter = migratingUnsupportedSafariPrivateTargets(current.linkRouter)
        }
        current.schemaVersion = PotliJiSettings.currentSchemaVersion
        try RuleTransfer().validate(current.linkRouter.rules)
        return current
    }

    private nonisolated static func legacyAlternativeReplacement(
        in settings: LinkRouterSettings
    ) -> RouteTarget {
        settings.alternativeTarget.kind == .alternativeBrowser
            ? .prompt
            : settings.alternativeTarget
    }

    private nonisolated static func replacingLegacyAlternativeTargets(
        in rules: [LinkRule],
        with replacement: RouteTarget
    ) -> [LinkRule] {
        rules.map { rule in
            guard rule.target.kind == .alternativeBrowser else { return rule }
            var migrated = rule
            migrated.target = replacement
            return migrated
        }
    }

    private nonisolated static func migratingRulesToCurrentModel(
        _ rules: [LinkRule]
    ) -> [LinkRule] {
        rules.map { rule in
            var migrated = rule
            migrated.target = replacingUnsupportedSafariPrivateTarget(migrated.target)
            if migrated.urlMatcherGroups == nil {
                migrated.urlMatcherGroups =
                    migrated.urlMatchers.isEmpty
                    ? []
                    : [URLMatcherGroup(mode: .all, matchers: migrated.urlMatchers)]
            }
            if migrated.editorKind == nil {
                migrated.editorKind = .advanced
            }
            return migrated
        }
    }

    private nonisolated static func migratingUnsupportedSafariPrivateTargets(
        _ settings: LinkRouterSettings
    ) -> LinkRouterSettings {
        var migrated = settings
        migrated.primaryTarget = replacingUnsupportedSafariPrivateTarget(migrated.primaryTarget)
        migrated.alternativeTarget = replacingUnsupportedSafariPrivateTarget(migrated.alternativeTarget)
        migrated.rules = migratingRulesToCurrentModel(migrated.rules)
        migrated.browserPresentation.removeAll { $0.id == "app.com.apple.Safari.private" }

        if let target = migrated.googleMeetTarget, isUnsupportedSafariPrivateTarget(target) {
            migrated.googleMeetTarget = nil
        }
        if let target = migrated.youtubeTarget, isUnsupportedSafariPrivateTarget(target) {
            migrated.youtubeTarget = nil
            migrated.youtubeRoutingEnabled = false
        }
        return migrated
    }

    private nonisolated static func replacingUnsupportedSafariPrivateTarget(
        _ target: RouteTarget
    ) -> RouteTarget {
        isUnsupportedSafariPrivateTarget(target) ? .prompt : target
    }

    private nonisolated static func isUnsupportedSafariPrivateTarget(_ target: RouteTarget) -> Bool {
        target.bundleIdentifier == "com.apple.Safari" && target.openMode == .privateWindow
    }

    private nonisolated static func merge(defaults: Any, stored: Any) -> Any {
        guard let defaultDictionary = defaults as? [String: Any],
            let storedDictionary = stored as? [String: Any]
        else {
            return stored
        }

        var result = defaultDictionary
        for (key, value) in storedDictionary {
            if let defaultValue = defaultDictionary[key] {
                result[key] = merge(defaults: defaultValue, stored: value)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

private actor SettingsPersistenceWriter {
    func write(_ settings: PotliJiSettings, to url: URL) throws {
        try RuleTransfer().validate(settings.linkRouter.rules)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(settings)
        guard data.count <= RuleTransfer.maximumDocumentBytes else {
            throw SettingsStoreError.settingsFileTooLarge(data.count)
        }
        try data.write(to: url, options: .atomic)
    }
}
