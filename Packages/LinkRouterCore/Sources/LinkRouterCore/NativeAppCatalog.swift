import Foundation

public enum NativeAppTransform: String, Codable, Sendable {
    case passThrough
    case replaceScheme
    case appStore
    case appleMusic
    case clickUp
    case discord
    case figma
    case linear
    case microsoftTeams
    case notion
    case spotify
    case telegram
    case zoom
}

public struct NativeAppDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var hostSuffixes: [String]
    public var pathPrefixes: [String]
    public var candidateBundleIdentifiers: [String]
    public var customScheme: String?
    public var transform: NativeAppTransform
    public var isEnabledByDefault: Bool

    public init(
        id: String,
        displayName: String,
        hostSuffixes: [String],
        pathPrefixes: [String] = [],
        candidateBundleIdentifiers: [String] = [],
        customScheme: String? = nil,
        transform: NativeAppTransform = .passThrough,
        isEnabledByDefault: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.hostSuffixes = hostSuffixes
        self.pathPrefixes = pathPrefixes
        self.candidateBundleIdentifiers = candidateBundleIdentifiers
        self.customScheme = customScheme
        self.transform = transform
        self.isEnabledByDefault = isEnabledByDefault
    }

    public func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let hostMatches = hostSuffixes.contains { suffix in
            let normalized = suffix.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == normalized || host.hasSuffix(".\(normalized)")
        }
        guard hostMatches else { return false }
        return pathPrefixes.isEmpty || pathPrefixes.contains(where: { url.path.hasPrefix($0) })
    }

    public func transformedURL(from webURL: URL) -> URL? {
        switch transform {
        case .passThrough:
            return webURL
        case .replaceScheme:
            guard let customScheme else { return webURL }
            return replacingScheme(of: webURL, with: customScheme)
        case .appStore:
            return replacingScheme(of: webURL, with: "macappstore")
        case .appleMusic:
            return replacingScheme(of: webURL, with: "music")
        case .clickUp:
            guard let components = URLComponents(url: webURL, resolvingAgainstBaseURL: false) else { return nil }
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var value = "clickup://\(path)"
            if let query = components.percentEncodedQuery, !query.isEmpty { value += "?\(query)" }
            return URL(string: value)
        case .discord:
            guard webURL.path.hasPrefix("/channels/") else {
                return URL(string: "discord://-/")
            }
            return URL(string: "discord://\(webURL.path)")
        case .figma:
            var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false)
            components?.scheme = "figma"
            return components?.url
        case .linear:
            return replacingScheme(of: webURL, with: "linear")
        case .microsoftTeams:
            return replacingScheme(of: webURL, with: "msteams")
        case .notion:
            return replacingScheme(of: webURL, with: "notion")
        case .spotify:
            let pieces = webURL.path.split(separator: "/").map(String.init)
            guard pieces.count >= 2 else { return URL(string: "spotify:") }
            return URL(string: "spotify:\(pieces[0]):\(pieces[1])")
        case .telegram:
            let path = webURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty else { return URL(string: "tg://") }
            if path.hasPrefix("joinchat/") || path.hasPrefix("+") {
                let token = path.replacingOccurrences(of: "joinchat/", with: "").trimmingCharacters(
                    in: CharacterSet(charactersIn: "+"))
                return URL(string: "tg://join?invite=\(token)")
            }
            let components = path.split(separator: "/").map(String.init)
            guard let domain = components.first else { return URL(string: "tg://") }
            var value = "tg://resolve?domain=\(domain)"
            if components.count > 1 { value += "&post=\(components[1])" }
            return URL(string: value)
        case .zoom:
            return zoomURL(from: webURL)
        }
    }

    private func replacingScheme(of url: URL, with scheme: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = scheme
        return components.url
    }

    private func zoomURL(from url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let markerIndex = parts.firstIndex(where: { $0 == "j" || $0 == "s" || $0 == "w" }),
            parts.indices.contains(markerIndex + 1)
        else {
            return replacingScheme(of: url, with: "zoommtg")
        }
        let meetingID = parts[markerIndex + 1]
        let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name.caseInsensitiveCompare("pwd") == .orderedSame })?.value
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = "zoom.us"
        components.path = "/join"
        var items = [URLQueryItem(name: "confno", value: meetingID)]
        if let password, !password.isEmpty { items.append(URLQueryItem(name: "pwd", value: password)) }
        components.queryItems = items
        return components.url
    }
}

public struct NativeAppCatalog: Sendable {
    public static let builtIns: [NativeAppDefinition] = [
        .init(
            id: "airtable", displayName: "Airtable", hostSuffixes: ["airtable.com"],
            candidateBundleIdentifiers: ["com.airtable.airtablemac", "com.airtable.desktop"], customScheme: "airtable",
            transform: .replaceScheme),
        .init(
            id: "amazon-chime", displayName: "Amazon Chime", hostSuffixes: ["chime.aws", "chime.aws.amazon.com"],
            candidateBundleIdentifiers: ["com.amazon.Amazon-Chime"], customScheme: "chime", transform: .replaceScheme),
        .init(
            id: "app-store", displayName: "App Store", hostSuffixes: ["apps.apple.com", "itunes.apple.com"],
            candidateBundleIdentifiers: ["com.apple.AppStore"], customScheme: "macappstore", transform: .appStore,
            isEnabledByDefault: true),
        .init(
            id: "apple-music", displayName: "Apple Music", hostSuffixes: ["music.apple.com"],
            candidateBundleIdentifiers: ["com.apple.Music"], customScheme: "music", transform: .appleMusic),
        .init(
            id: "around", displayName: "Around", hostSuffixes: ["around.co"],
            candidateBundleIdentifiers: ["com.team.video", "co.around.Around"], customScheme: "around",
            transform: .replaceScheme),
        .init(
            id: "asana", displayName: "Asana", hostSuffixes: ["app.asana.com", "asana.com"],
            candidateBundleIdentifiers: ["com.asana.app", "com.asana.desktop"], customScheme: "asana",
            transform: .replaceScheme),
        .init(
            id: "clickup", displayName: "ClickUp", hostSuffixes: ["app.clickup.com", "clickup.com"],
            candidateBundleIdentifiers: ["com.clickup.desktop-app", "com.clickup.ClickUp"], customScheme: "clickup",
            transform: .clickUp),
        .init(
            id: "discord", displayName: "Discord", hostSuffixes: ["discord.com", "discordapp.com"],
            candidateBundleIdentifiers: ["com.hnc.Discord"], customScheme: "discord", transform: .discord),
        .init(
            id: "figma", displayName: "Figma", hostSuffixes: ["figma.com"],
            candidateBundleIdentifiers: ["com.figma.Desktop"], customScheme: "figma", transform: .figma),
        .init(
            id: "front", displayName: "Front", hostSuffixes: ["app.frontapp.com", "front.com"],
            candidateBundleIdentifiers: ["com.frontapp.Front"], customScheme: "front", transform: .replaceScheme),
        .init(
            id: "jitsi", displayName: "Jitsi Meet", hostSuffixes: ["meet.jit.si"],
            candidateBundleIdentifiers: ["org.jitsi.jitsi-meet", "org.jitsi.Jitsi-Meet"], customScheme: "jitsi-meet",
            transform: .replaceScheme),
        .init(
            id: "linear", displayName: "Linear", hostSuffixes: ["linear.app"],
            candidateBundleIdentifiers: ["com.linear", "com.linear.desktop"], customScheme: "linear", transform: .linear
        ),
        .init(
            id: "mastodon", displayName: "Mastodon", hostSuffixes: ["mastodon.social", "mstdn.social", "hachyderm.io"],
            candidateBundleIdentifiers: ["com.tapbots.Ivory", "com.theiconfactory.Tapestry", "com.voidworks.Mona"],
            transform: .passThrough),
        .init(
            id: "microsoft-teams", displayName: "Microsoft Teams",
            hostSuffixes: ["teams.microsoft.com", "teams.live.com"],
            candidateBundleIdentifiers: ["com.microsoft.teams2", "com.microsoft.teams"], customScheme: "msteams",
            transform: .microsoftTeams),
        .init(
            id: "miro", displayName: "Miro", hostSuffixes: ["miro.com"],
            candidateBundleIdentifiers: ["com.electron.realtimeboard", "com.miro.desktop"], customScheme: "miro",
            transform: .replaceScheme),
        .init(
            id: "notion", displayName: "Notion", hostSuffixes: ["notion.so", "notion.site"],
            candidateBundleIdentifiers: ["notion.id"], customScheme: "notion", transform: .notion),
        .init(
            id: "pop", displayName: "Pop", hostSuffixes: ["pop.com", "screen.so"],
            candidateBundleIdentifiers: ["com.getpop.Pop", "so.screen.Screen"], customScheme: "pop",
            transform: .replaceScheme),
        .init(
            id: "reddit", displayName: "Reddit", hostSuffixes: ["reddit.com", "redd.it"],
            candidateBundleIdentifiers: ["com.reddit.Reddit"], transform: .passThrough),
        .init(
            id: "slite", displayName: "Slite", hostSuffixes: ["slite.com"],
            candidateBundleIdentifiers: ["com.slite.desktop"], customScheme: "slite", transform: .replaceScheme),
        .init(
            id: "spotify", displayName: "Spotify", hostSuffixes: ["open.spotify.com"],
            candidateBundleIdentifiers: ["com.spotify.client"], customScheme: "spotify", transform: .spotify),
        .init(
            id: "telegram", displayName: "Telegram", hostSuffixes: ["t.me", "telegram.me", "telegram.dog"],
            candidateBundleIdentifiers: ["ru.keepcoder.Telegram", "org.telegram.desktop"], customScheme: "tg",
            transform: .telegram),
        .init(
            id: "tidal", displayName: "TIDAL", hostSuffixes: ["tidal.com", "listen.tidal.com"],
            candidateBundleIdentifiers: ["com.tidal.desktop"], customScheme: "tidal", transform: .replaceScheme),
        .init(
            id: "trello", displayName: "Trello", hostSuffixes: ["trello.com"],
            candidateBundleIdentifiers: ["com.trello.trello"], customScheme: "trello", transform: .replaceScheme),
        .init(
            id: "twitter", displayName: "X / Twitter", hostSuffixes: ["x.com", "twitter.com"],
            candidateBundleIdentifiers: ["com.twitter.twitter-mac", "maccatalyst.com.atebits.Tweetie2"],
            transform: .passThrough),
        .init(
            id: "zeplin", displayName: "Zeplin", hostSuffixes: ["app.zeplin.io", "zeplin.io"],
            candidateBundleIdentifiers: ["io.zeplin.osx"], customScheme: "zeplin", transform: .replaceScheme),
        .init(
            id: "zoom", displayName: "Zoom", hostSuffixes: ["zoom.us"], pathPrefixes: ["/j/", "/s/", "/w/"],
            candidateBundleIdentifiers: ["us.zoom.xos"], customScheme: "zoommtg", transform: .zoom),
    ]

    public init() {}

    public func match(url: URL, enabledIDs: Set<String>) -> NativeAppDefinition? {
        Self.builtIns.first { enabledIDs.contains($0.id) && $0.matches(url) }
    }
}
