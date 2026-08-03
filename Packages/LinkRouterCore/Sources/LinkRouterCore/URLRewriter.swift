import Foundation

public enum RuleEditorKind: String, Codable, Sendable {
    case guided
    case advanced
}

public enum URLRewriteKind: String, Codable, CaseIterable, Sendable {
    case replaceHost
    case forceHTTPS
    case replacePathPrefix
    case removeQueryParameters
    case setQueryParameter
}

public struct URLRewriteAction: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: URLRewriteKind
    public var value: String
    public var replacement: String

    public init(
        id: UUID = UUID(),
        kind: URLRewriteKind,
        value: String = "",
        replacement: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.replacement = replacement
    }
}

public enum URLRewriterError: LocalizedError {
    case invalidURL
    case invalidHost(String)
    case unsupportedScheme(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The rewrite did not produce a valid URL."
        case .invalidHost(let host):
            return "“\(host)” is not a valid website domain."
        case .unsupportedScheme(let scheme):
            return "The rewritten URL uses the unsupported “\(scheme)” scheme."
        }
    }
}

public struct StructuredURLRewriter: Sendable {
    public init() {}

    public func rewrite(_ input: URL, actions: [URLRewriteAction]) throws -> URL {
        guard var components = URLComponents(url: input, resolvingAgainstBaseURL: false) else {
            throw URLRewriterError.invalidURL
        }

        for action in actions {
            switch action.kind {
            case .replaceHost:
                let host = Self.normalizedHost(action.value)
                guard Self.isValidHost(host) else { throw URLRewriterError.invalidHost(action.value) }
                components.host = host
            case .forceHTTPS:
                components.scheme = "https"
            case .replacePathPrefix:
                guard components.path.hasPrefix(action.value) else { continue }
                components.path = action.replacement + components.path.dropFirst(action.value.count)
            case .removeQueryParameters:
                let names = Set(
                    action.value
                        .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                        .map { $0.lowercased() }
                )
                components.queryItems = components.queryItems?.filter { !names.contains($0.name.lowercased()) }
            case .setQueryParameter:
                let name = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                var items = components.queryItems ?? []
                items.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                items.append(URLQueryItem(name: name, value: action.replacement))
                components.queryItems = items
            }
        }

        guard let output = components.url else { throw URLRewriterError.invalidURL }
        let scheme = output.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            throw URLRewriterError.unsupportedScheme(scheme)
        }
        return output
    }

    private static func normalizedHost(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private static func isValidHost(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253, !value.contains("..") else { return false }
        return value.split(separator: ".").allSatisfy { label in
            guard !label.isEmpty, label.utf8.count <= 63,
                label.first != "-", label.last != "-"
            else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
