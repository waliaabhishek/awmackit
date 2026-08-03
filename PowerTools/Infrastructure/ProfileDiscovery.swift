import Foundation

struct ProfileDiscovery {
    private let fileManager = FileManager.default

    func discoverProfiles(for browser: BrowserInstallation) -> [BrowserProfile] {
        if browser.supportsChromiumProfiles {
            return discoverChromiumProfiles(for: browser)
        }
        if browser.supportsFirefoxProfiles {
            return discoverFirefoxProfiles(for: browser)
        }
        return []
    }

    func discoverPWAs(browsers: [BrowserInstallation]) -> [BrowserPWA] {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Applications/Chrome Apps.localized", isDirectory: true),
            home.appendingPathComponent("Applications/Chrome Apps", isDirectory: true),
        ]

        var results: [BrowserPWA] = []
        var seen = Set<String>()
        for root in roots where fileManager.fileExists(atPath: root.path) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .nameKey]
            guard
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else { continue }

            for case let appURL as URL in enumerator where appURL.pathExtension == "app" {
                guard seen.insert(appURL.standardizedFileURL.path).inserted,
                    let bundle = Bundle(url: appURL),
                    let info = bundle.infoDictionary
                else { continue }

                let appID = info["CrAppModeShortcutID"] as? String
                let profile = info["CrAppModeProfileDir"] as? String
                let userDataDir = info["CrAppModeUserDataDir"] as? String
                guard appID != nil || profile != nil || userDataDir != nil else { continue }

                let parent = browsers.first { browser in
                    if let userDataDir {
                        return userDataDirectory(for: browser)?.standardizedFileURL.path
                            == URL(fileURLWithPath: userDataDir).standardizedFileURL.path
                    }
                    return false
                }

                results.append(
                    BrowserPWA(
                        id: "pwa.\(appURL.path)",
                        displayName: (info["CFBundleDisplayName"] as? String)
                            ?? (info["CFBundleName"] as? String)
                                ?? appURL.deletingPathExtension().lastPathComponent,
                        applicationURL: appURL,
                        parentBrowserBundleIdentifier: parent?.bundleIdentifier,
                        parentBrowserApplicationURL: parent?.applicationURL,
                        profileIdentifier: profile,
                        appIdentifier: appID
                    ))
            }
        }

        return results.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func discoverChromiumProfiles(for browser: BrowserInstallation) -> [BrowserProfile] {
        guard let directory = userDataDirectory(for: browser) else { return [] }
        let localStateURL = directory.appendingPathComponent("Local State")
        guard let data = try? BoundedFileReader.read(from: localStateURL, maximumBytes: 4 * 1_024 * 1_024),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let infoCache = profile["info_cache"] as? [String: [String: Any]]
        else {
            return fallbackChromiumProfiles(directory: directory, browser: browser)
        }

        return infoCache.compactMap { identifier, metadata in
            let name = (metadata["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            return BrowserProfile(
                id: "profile.\(browser.bundleIdentifier).\(identifier)",
                browserBundleIdentifier: browser.bundleIdentifier,
                browserName: browser.displayName,
                browserApplicationURL: browser.applicationURL,
                profileIdentifier: identifier,
                profileName: name,
                kind: .chromium
            )
        }
        .sorted { $0.profileName.localizedStandardCompare($1.profileName) == .orderedAscending }
    }

    private func fallbackChromiumProfiles(directory: URL, browser: BrowserInstallation) -> [BrowserProfile] {
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        return entries.compactMap { url in
            let name = url.lastPathComponent
            guard name == "Default" || name.hasPrefix("Profile ") else { return nil }
            let preferencesURL = url.appendingPathComponent("Preferences")
            var displayName = name == "Default" ? "Default" : name
            if let data = try? BoundedFileReader.read(from: preferencesURL, maximumBytes: 4 * 1_024 * 1_024),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let profile = root["profile"] as? [String: Any],
                let configuredName = profile["name"] as? String,
                !configuredName.isEmpty
            {
                displayName = configuredName
            }
            return BrowserProfile(
                id: "profile.\(browser.bundleIdentifier).\(name)",
                browserBundleIdentifier: browser.bundleIdentifier,
                browserName: browser.displayName,
                browserApplicationURL: browser.applicationURL,
                profileIdentifier: name,
                profileName: displayName,
                kind: .chromium
            )
        }
    }

    private func discoverFirefoxProfiles(for browser: BrowserInstallation) -> [BrowserProfile] {
        guard let root = firefoxRootDirectory(for: browser) else { return [] }
        let profilesINI = root.appendingPathComponent("profiles.ini")
        guard let data = try? BoundedFileReader.read(from: profilesINI, maximumBytes: 1 * 1_024 * 1_024),
            let text = String(data: data, encoding: .utf8)
        else { return [] }
        let sections = INIParser.parse(text)

        return sections.compactMap { name, values in
            guard name.hasPrefix("Profile"),
                let profileName = values["Name"],
                let path = values["Path"]
            else { return nil }

            // Firefox's newer profile manager writes human-readable names and profile groups.
            // Legacy about:profiles entries still parse, but the launcher can surface a warning.
            return BrowserProfile(
                id: "profile.\(browser.bundleIdentifier).\(path)",
                browserBundleIdentifier: browser.bundleIdentifier,
                browserName: browser.displayName,
                browserApplicationURL: browser.applicationURL,
                profileIdentifier: profileName,
                profileName: profileName,
                kind: .firefox
            )
        }
        .sorted { $0.profileName.localizedStandardCompare($1.profileName) == .orderedAscending }
    }

    private func userDataDirectory(for browser: BrowserInstallation) -> URL? {
        let support = applicationSupportDirectory
        let relativePath: String?
        switch browser.bundleIdentifier {
        case "com.google.Chrome": relativePath = "Google/Chrome"
        case "com.google.Chrome.beta": relativePath = "Google/Chrome Beta"
        case "com.google.Chrome.canary": relativePath = "Google/Chrome Canary"
        case "com.google.Chrome.dev": relativePath = "Google/Chrome Dev"
        case "com.microsoft.edgemac": relativePath = "Microsoft Edge"
        case "com.microsoft.edgemac.Beta": relativePath = "Microsoft Edge Beta"
        case "com.microsoft.edgemac.Canary": relativePath = "Microsoft Edge Canary"
        case "com.microsoft.edgemac.Dev": relativePath = "Microsoft Edge Dev"
        case "com.brave.Browser": relativePath = "BraveSoftware/Brave-Browser"
        case "com.brave.Browser.beta": relativePath = "BraveSoftware/Brave-Browser-Beta"
        case "com.brave.Browser.nightly": relativePath = "BraveSoftware/Brave-Browser-Nightly"
        case "com.brave.Browser.origin": relativePath = "BraveSoftware/Brave-Origin"
        case "com.vivaldi.Vivaldi": relativePath = "Vivaldi"
        case "com.vivaldi.Vivaldi.snapshot": relativePath = "Vivaldi Snapshot"
        case "org.chromium.Chromium": relativePath = "Chromium"
        case "ai.perplexity.comet": relativePath = "Comet"
        case "net.imput.helium": relativePath = "Helium"
        case "org.chromium.Thorium": relativePath = "Thorium"
        case "com.bookry.wavebox": relativePath = "Wavebox"
        default: relativePath = nil
        }
        guard let relativePath else { return nil }
        return support.appendingPathComponent(relativePath, isDirectory: true)
    }

    private func firefoxRootDirectory(for browser: BrowserInstallation) -> URL? {
        let support = applicationSupportDirectory
        switch browser.bundleIdentifier {
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly":
            return support.appendingPathComponent("Firefox", isDirectory: true)
        case "app.zen-browser.zen", "io.github.zen_browser.zen":
            return support.appendingPathComponent("zen", isDirectory: true)
        default:
            return nil
        }
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }
}

private enum INIParser {
    static func parse(_ text: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var currentSection: String?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                if let currentSection { result[currentSection, default: [:]] = [:] }
                continue
            }
            guard let currentSection,
                let separator = line.firstIndex(of: "=")
            else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            result[currentSection, default: [:]][key] = value
        }

        return result
    }
}
