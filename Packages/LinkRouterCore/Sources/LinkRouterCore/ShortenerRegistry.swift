import Foundation

public struct ShortenerRegistry: Sendable {
    public static let builtInHosts: Set<String> = [
        "1url.com", "amzn.to", "apple.co", "apple.news", "bit.do", "bit.ly", "buff.ly",
        "chilp.it", "clck.ru", "cutt.ly", "db.tt", "discord.gg", "dlvr.it", "engt.co",
        "fb.me", "forms.gle", "goo.gl", "ht.ly", "ift.tt", "is.gd", "j.mp", "kutt.it",
        "lnkd.in", "maps.app.goo.gl", "mzl.la", "nyti.ms", "ow.ly", "rb.gy", "rebrand.ly",
        "s.id", "shorturl.at", "spoti.fi", "t.co", "t.ly", "t.me", "tiny.cc", "tiny.one",
        "tinyurl.com", "trib.al", "youtu.be", "zeep.ly", "zoom.us",
    ]

    public var customHosts: Set<String>

    public init(customHosts: Set<String> = []) {
        self.customHosts = Set(customHosts.map(Self.normalize))
    }

    public func contains(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let normalized = Self.normalize(host)
        return Self.builtInHosts.contains(normalized) || customHosts.contains(normalized)
    }

    public func containsBuiltIn(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return Self.builtInHosts.contains(Self.normalize(host))
    }

    public static func normalize(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
