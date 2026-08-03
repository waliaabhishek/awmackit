import Foundation

public struct RuleEngine: Sendable {
    public init() {}

    public func ordered(_ rules: [LinkRule]) -> [LinkRule] {
        rules.sorted(by: Self.precedes)
    }

    public func firstMatch(
        for url: URL,
        sourceApplication: SourceApplication?,
        rules: [LinkRule]
    ) -> RuleMatch? {
        firstMatch(
            for: url,
            sourceApplication: sourceApplication,
            orderedRules: ordered(rules)
        )
    }

    public func firstMatch(
        for url: URL,
        sourceApplication: SourceApplication?,
        orderedRules: [LinkRule]
    ) -> RuleMatch? {

        guard let rule = orderedRules.first(where: { $0.matches(url: url, sourceApplication: sourceApplication) })
        else {
            return nil
        }

        return RuleMatch(rule: rule, target: rule.target)
    }

    public func matchingRules(
        for url: URL,
        sourceApplication: SourceApplication?,
        rules: [LinkRule]
    ) -> [LinkRule] {
        rules
            .filter { $0.matches(url: url, sourceApplication: sourceApplication) }
            .sorted(by: Self.precedes)
    }

    private static func precedes(_ lhs: LinkRule, _ rhs: LinkRule) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.priority > rhs.priority
    }
}
