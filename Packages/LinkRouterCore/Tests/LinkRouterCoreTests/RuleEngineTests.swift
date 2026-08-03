import XCTest

@testable import LinkRouterCore

final class RuleEngineTests: XCTestCase {
    func testHostAndSourceAppRule() throws {
        let url = try XCTUnwrap(URL(string: "https://docs.example.com/work/item/1"))
        let source = SourceApplication(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")
        let target = RouteTarget(
            id: "chrome.work",
            kind: .browserProfile,
            displayName: "Chrome — Work",
            bundleIdentifier: "com.google.Chrome",
            profileIdentifier: "Profile 2",
            profileName: "Work"
        )
        let rule = LinkRule(
            name: "Work links from Slack",
            priority: 100,
            urlMatchers: [URLMatcher(kind: .hostSuffix, pattern: "example.com")],
            sourceAppMatchers: [SourceAppMatcher(bundleIdentifier: "com.tinyspeck.slackmacgap")],
            target: target
        )

        let match = RuleEngine().firstMatch(for: url, sourceApplication: source, rules: [rule])
        XCTAssertEqual(match?.target, target)
    }

    func testHigherPriorityRuleWins() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let low = LinkRule(name: "Low", priority: 1, target: .primary)
        let high = LinkRule(name: "High", priority: 10, target: .prompt)
        XCTAssertEqual(
            RuleEngine().firstMatch(for: url, sourceApplication: nil, rules: [low, high])?.rule.name, "High")
    }

    func testRegexMatcher() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/tickets/ABC-123"))
        let matcher = URLMatcher(kind: .regularExpression, pattern: #"/tickets/[A-Z]+-\d+$"#)
        XCTAssertTrue(matcher.matches(url))
    }

    func testWebsiteFamilyMatchersAreAlternativesWithinAGroup() throws {
        let rule = LinkRule(
            name: "YouTube",
            urlMatcherGroups: [
                URLMatcherGroup(
                    mode: .any,
                    matchers: [
                        URLMatcher(kind: .hostSuffix, pattern: "youtube.com"),
                        URLMatcher(kind: .host, pattern: "youtu.be"),
                    ]
                )
            ],
            target: .primary
        )
        let youtube = try XCTUnwrap(URL(string: "https://music.youtube.com/watch?v=123"))
        let shortLink = try XCTUnwrap(URL(string: "https://youtu.be/123"))
        let unrelated = try XCTUnwrap(URL(string: "https://example.com/"))

        XCTAssertTrue(rule.matches(url: youtube, sourceApplication: nil))
        XCTAssertTrue(rule.matches(url: shortLink, sourceApplication: nil))
        XCTAssertFalse(rule.matches(url: unrelated, sourceApplication: nil))
    }
    func testMultiplePositiveSourceAppsAreAlternatives() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let source = SourceApplication(bundleIdentifier: "com.apple.mail", name: "Mail")
        let rule = LinkRule(
            name: "Links from chat or mail",
            urlMatchers: [URLMatcher(kind: .host, pattern: "example.com")],
            sourceAppMatchers: [
                SourceAppMatcher(bundleIdentifier: "com.tinyspeck.slackmacgap"),
                SourceAppMatcher(bundleIdentifier: "com.apple.mail"),
            ],
            target: .primary
        )
        XCTAssertNotNil(RuleEngine().firstMatch(for: url, sourceApplication: source, rules: [rule]))
    }

    func testNegatedSourceAppExcludesMatchingApplication() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let source = SourceApplication(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let rule = LinkRule(
            name: "Except Safari",
            sourceAppMatchers: [SourceAppMatcher(bundleIdentifier: "com.apple.Safari", isNegated: true)],
            target: .primary
        )
        XCTAssertNil(RuleEngine().firstMatch(for: url, sourceApplication: source, rules: [rule]))
    }

    func testPreparedRulesCanBeReusedWithoutSortingAgain() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let rules = (0..<1_000).map { index in
            LinkRule(
                name: "Rule \(index)",
                priority: index,
                urlMatchers: [URLMatcher(kind: .host, pattern: index == 999 ? "example.com" : "other.example")],
                target: .primary
            )
        }
        let engine = RuleEngine()
        let ordered = engine.ordered(rules)

        measure {
            for _ in 0..<100 {
                XCTAssertEqual(
                    engine.firstMatch(for: url, sourceApplication: nil, orderedRules: ordered)?.rule.name,
                    "Rule 999"
                )
            }
        }
    }

}
