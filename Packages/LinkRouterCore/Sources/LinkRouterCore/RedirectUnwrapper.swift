import Foundation

public struct RedirectUnwrapResult: Sendable, Equatable {
    public var url: URL
    public var hops: [URL]

    public init(url: URL, hops: [URL]) {
        self.url = url
        self.hops = hops
    }
}

public struct RedirectUnwrapper: Sendable {
    public init() {}

    public func unwrap(_ input: URL, maximumDepth: Int = 8) -> RedirectUnwrapResult {
        var current = input
        var hops: [URL] = []
        var visited = Set<String>()

        for _ in 0..<maximumDepth {
            guard visited.insert(current.absoluteString).inserted else { break }
            guard let next = embeddedDestination(in: current), next != current else { break }
            hops.append(next)
            current = next
        }

        return RedirectUnwrapResult(url: current, hops: hops)
    }

    public func embeddedDestination(in url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let query = Dictionary(grouping: components.queryItems ?? [], by: { $0.name.lowercased() })
        func value(_ names: String...) -> String? {
            for name in names {
                if let result = query[name.lowercased()]?.first?.value, !result.isEmpty {
                    return result
                }
            }
            return nil
        }

        let candidates: [String?]
        switch host {
        case "www.google.com", "google.com", "google.co.uk", "google.ca", "google.de", "google.fr":
            guard url.path == "/url" || url.path == "/imgres" else { return nil }
            candidates = [value("q", "url", "imgurl")]
        case "l.facebook.com", "lm.facebook.com", "l.instagram.com":
            candidates = [value("u", "url")]
        case "slack-redir.net", "slack.com":
            candidates = [value("url", "u")]
        case let host where host.hasSuffix(".safelinks.protection.outlook.com"):
            candidates = [value("url")]
        case "www.youtube.com", "youtube.com":
            guard url.path == "/redirect" else { return nil }
            candidates = [value("q", "url")]
        case "href.li":
            candidates = [components.percentEncodedQuery]
        case "r.search.yahoo.com":
            // Yahoo redirect URLs commonly encode the destination between /RU= and /RK=.
            let absolute = url.absoluteString
            if let start = absolute.range(of: "/RU="),
                let end = absolute.range(of: "/RK=", range: start.upperBound..<absolute.endIndex)
            {
                candidates = [String(absolute[start.upperBound..<end.lowerBound])]
            } else {
                candidates = []
            }
        default:
            // Unknown hosts are intentionally not guessed. Substring heuristics such as
            // matching "out" also match ordinary paths like "/about" and can silently
            // replace a legitimate page with an unrelated query-parameter URL.
            candidates = []
        }

        for candidate in candidates.compactMap({ $0 }) {
            for decoded in decodeCandidates(candidate) {
                if let destination = URL(string: decoded),
                    let scheme = destination.scheme?.lowercased(),
                    ["http", "https"].contains(scheme)
                {
                    return destination
                }
            }
        }

        return nil
    }

    private func decodeCandidates(_ value: String) -> [String] {
        var results = [value]
        var current = value
        for _ in 0..<3 {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            results.append(decoded)
            current = decoded
        }
        return results
    }
}
