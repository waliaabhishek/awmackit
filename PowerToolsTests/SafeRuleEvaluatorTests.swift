import LinkRouterCore
import XCTest

@testable import PowerTools

final class SafeRuleEvaluatorTests: XCTestCase {
    func testRegexRuleRunsInHelperProcess() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/tickets/ABC-123"))
        let rule = LinkRule(
            name: "Ticket",
            urlMatchers: [URLMatcher(kind: .regularExpression, pattern: #"/tickets/[A-Z]+-\d+$"#)],
            target: .primary
        )
        let result = try await SafeRuleEvaluator().firstMatch(
            for: url,
            sourceApplication: nil,
            orderedRules: [rule]
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
        _ = try? await SafeRuleEvaluator().firstMatch(
            for: url,
            sourceApplication: nil,
            orderedRules: [rule]
        )
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }
}
