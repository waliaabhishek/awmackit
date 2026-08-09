import LinkRouterCore
import XCTest

@testable import PotliJi

final class SafeRuleEvaluatorTests: XCTestCase {
    func testRegexRuleRunsInHelperProcess() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/tickets/ABC-123"))
        let rule = LinkRule(
            name: "Ticket",
            urlMatchers: [URLMatcher(kind: .regularExpression, pattern: #"/tickets/[A-Z]+-\d+$"#)],
            target: .primary
        )
        let evaluator = SafeRuleEvaluator()
        let preparedRules = try await evaluator.prepare([rule])
        let result = try await evaluator.firstMatch(
            for: url,
            sourceApplication: nil,
            preparedRules: preparedRules
        )
        XCTAssertEqual(result?.rule.id, rule.id)
    }

    func testPathologicalRegexCannotBlockCallerIndefinitely() async throws {
        let path = String(repeating: "a", count: 50_000) + "!"
        let url = try XCTUnwrap(URL(string: "https://example.com/\(path)"))
        let rule = LinkRule(
            name: "Pathological",
            urlMatchers: [URLMatcher(kind: .regularExpression, pattern: "(a+)+$")],
            target: .primary
        )
        let start = ContinuousClock.now
        let evaluator = SafeRuleEvaluator()
        let preparedRules = try await evaluator.prepare([rule])
        _ = try? await evaluator.firstMatch(
            for: url,
            sourceApplication: nil,
            preparedRules: preparedRules
        )
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testMaximumAcceptedNonRegexRuleSetDoesNotRequireHelperEncoding() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/target"))
        let filler = String(repeating: "x", count: 600)
        var rules = (0..<(RuleTransfer.maximumRuleCount - 1)).map { index in
            LinkRule(
                name: "Rule \(index)",
                urlMatchers: [URLMatcher(kind: .contains, pattern: "\(filler)\(index)")],
                target: .prompt
            )
        }
        let matchingRule = LinkRule(
            name: "Target",
            priority: -1,
            urlMatchers: [URLMatcher(kind: .host, pattern: "example.com")],
            target: .primary
        )
        rules.append(matchingRule)
        XCTAssertLessThan(try RuleTransfer().encode(rules).count, RuleTransfer.maximumDocumentBytes)

        let evaluator = SafeRuleEvaluator()
        let preparedRules = try await evaluator.prepare(rules)
        let result = try await evaluator.firstMatch(
            for: url,
            sourceApplication: nil,
            preparedRules: preparedRules
        )

        XCTAssertEqual(result?.rule.id, matchingRule.id)
    }

    func testLaterPathologicalRegexDoesNotDelayEarlierSimpleMatch() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let simpleRule = LinkRule(
            name: "Simple",
            priority: 100,
            urlMatchers: [URLMatcher(kind: .host, pattern: "example.com")],
            target: .primary
        )
        let pathologicalRule = LinkRule(
            name: "Pathological",
            priority: 0,
            urlMatchers: [URLMatcher(kind: .regularExpression, pattern: "(a+)+$")],
            target: .prompt
        )
        let evaluator = SafeRuleEvaluator()
        let preparedRules = try await evaluator.prepare([pathologicalRule, simpleRule])
        let start = ContinuousClock.now

        let result = try await evaluator.firstMatch(
            for: url,
            sourceApplication: nil,
            preparedRules: preparedRules
        )

        XCTAssertEqual(result?.rule.id, simpleRule.id)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(100))
    }

    func testBatchEvaluationPreservesPerURLPriority() async throws {
        let docsRule = LinkRule(
            name: "Docs",
            priority: 100,
            urlMatchers: [URLMatcher(kind: .regularExpression, pattern: #"/docs(?:/|$)"#)],
            target: .primary
        )
        let fallbackRule = LinkRule(
            name: "Fallback",
            priority: 0,
            urlMatchers: [URLMatcher(kind: .host, pattern: "example.com")],
            target: .prompt
        )
        let urls = try [
            XCTUnwrap(URL(string: "https://example.com/docs/start")),
            XCTUnwrap(URL(string: "https://example.com/blog")),
            XCTUnwrap(URL(string: "https://elsewhere.test/")),
        ]
        let evaluator = SafeRuleEvaluator()
        let preparedRules = try await evaluator.prepare([fallbackRule, docsRule])

        let matches = try await evaluator.firstMatches(
            for: urls,
            sourceApplication: nil,
            preparedRules: preparedRules
        )

        XCTAssertEqual(matches.map { $0?.rule.id }, [docsRule.id, fallbackRule.id, nil])
    }

    func testHelperEnvelopeCoversMaximumAcceptedRuleDocument() {
        XCTAssertGreaterThan(
            RuleMatchHelper.maximumRequestBytes,
            RuleTransfer.maximumDocumentBytes
        )
    }
}
