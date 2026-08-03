import Foundation

public struct RuleExportDocument: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var exportedAt: Date
    public var rules: [LinkRule]

    public init(schemaVersion: Int = currentSchemaVersion, exportedAt: Date = Date(), rules: [LinkRule]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.rules = rules
    }
}

public enum RuleTransferError: LocalizedError {
    case unsupportedSchema(Int)
    case documentTooLarge(Int)
    case tooManyRules(Int)
    case tooManyMatchers(String)
    case matcherPatternTooLong(String)
    case invalidRegularExpression(String)
    case tooManyRewriteActions(String)
    case rewriteValueTooLong(String)
    case transformScriptTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "The rule file uses unsupported schema version \(version)."
        case .documentTooLarge(let byteCount):
            return "The rule file is \(byteCount) bytes; the maximum is \(RuleTransfer.maximumDocumentBytes)."
        case .tooManyRules(let count):
            return "The rule file contains \(count) rules; the maximum is \(RuleTransfer.maximumRuleCount)."
        case .tooManyMatchers(let name):
            return "The rule “\(name)” contains too many matchers."
        case .matcherPatternTooLong(let name):
            return "The rule “\(name)” contains a matcher pattern longer than 4 KB."
        case .invalidRegularExpression(let name):
            return "The rule “\(name)” contains an invalid regular expression."
        case .tooManyRewriteActions(let name):
            return "The rule “\(name)” contains too many URL rewrite actions."
        case .rewriteValueTooLong(let name):
            return "The rule “\(name)” contains a URL rewrite value longer than 4 KB."
        case .transformScriptTooLarge(let name):
            return "The JavaScript transform in “\(name)” exceeds 64 KB."
        }
    }
}

public struct RuleTransfer: Sendable {
    public static let maximumRuleCount = 5_000
    public static let maximumDocumentBytes = 16 * 1_024 * 1_024
    public static let maximumMatchersPerRule = 128
    public static let maximumPatternBytes = 4 * 1_024
    public static let maximumRewriteActionsPerRule = 64
    public static let maximumScriptBytes = 64 * 1_024

    public init() {}

    public func encode(_ rules: [LinkRule], prettyPrinted: Bool = true) throws -> Data {
        try validate(rules)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        let data = try encoder.encode(RuleExportDocument(rules: rules))
        guard data.count <= Self.maximumDocumentBytes else {
            throw RuleTransferError.documentTooLarge(data.count)
        }
        return data
    }

    public func decode(_ data: Data) throws -> [LinkRule] {
        guard data.count <= Self.maximumDocumentBytes else {
            throw RuleTransferError.documentTooLarge(data.count)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(RuleExportDocument.self, from: data)
        guard document.schemaVersion <= RuleExportDocument.currentSchemaVersion else {
            throw RuleTransferError.unsupportedSchema(document.schemaVersion)
        }
        try validate(document.rules)
        return document.rules
    }

    public func validate(_ rules: [LinkRule]) throws {
        guard rules.count <= Self.maximumRuleCount else {
            throw RuleTransferError.tooManyRules(rules.count)
        }
        for rule in rules {
            let groupedMatchers = rule.urlMatcherGroups?.flatMap(\.matchers) ?? []
            let urlMatchers = rule.urlMatcherGroups == nil ? rule.urlMatchers : groupedMatchers
            guard urlMatchers.count + rule.sourceAppMatchers.count <= Self.maximumMatchersPerRule else {
                throw RuleTransferError.tooManyMatchers(rule.name)
            }
            for matcher in urlMatchers {
                guard matcher.pattern.utf8.count <= Self.maximumPatternBytes else {
                    throw RuleTransferError.matcherPatternTooLong(rule.name)
                }
                if matcher.kind == .regularExpression {
                    let options: NSRegularExpression.Options = matcher.isCaseSensitive ? [] : [.caseInsensitive]
                    do {
                        _ = try NSRegularExpression(pattern: matcher.pattern, options: options)
                    } catch {
                        throw RuleTransferError.invalidRegularExpression(rule.name)
                    }
                }
            }
            let rewriteActions = rule.rewriteActions ?? []
            guard rewriteActions.count <= Self.maximumRewriteActionsPerRule else {
                throw RuleTransferError.tooManyRewriteActions(rule.name)
            }
            guard
                rewriteActions.allSatisfy({
                    $0.value.utf8.count <= Self.maximumPatternBytes
                        && $0.replacement.utf8.count <= Self.maximumPatternBytes
                })
            else {
                throw RuleTransferError.rewriteValueTooLong(rule.name)
            }
            if let script = rule.transformJavaScript,
                script.utf8.count > Self.maximumScriptBytes
            {
                throw RuleTransferError.transformScriptTooLarge(rule.name)
            }
        }
    }
}
