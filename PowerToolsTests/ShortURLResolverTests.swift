import LinkRouterCore
import XCTest

@testable import PowerTools

final class ShortURLResolverTests: XCTestCase {
    func testUnknownInputReturnsWithoutNetworkResolution() async throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/article"))

        let result = try await ShortURLResolver().resolve(input, maximumRedirects: 10)

        XCTAssertEqual(result, input)
    }

    func testArbitraryDestinationIsReturnedWithoutBeingFetched() throws {
        let current = try XCTUnwrap(URL(string: "https://bit.ly/example"))

        let decision = try ShortURLResolver.redirectDecision(
            from: current,
            location: "https://example.com/article"
        )

        XCTAssertEqual(decision, .finish(try XCTUnwrap(URL(string: "https://example.com/article"))))
    }

    func testBuiltInShortenerHopMayBeFetched() throws {
        let current = try XCTUnwrap(URL(string: "https://bit.ly/example"))

        let decision = try ShortURLResolver.redirectDecision(
            from: current,
            location: "https://tinyurl.com/next"
        )

        XCTAssertEqual(decision, .fetch(try XCTUnwrap(URL(string: "https://tinyurl.com/next"))))
    }

    func testNonWebRedirectIsRejected() throws {
        let current = try XCTUnwrap(URL(string: "https://bit.ly/example"))

        XCTAssertThrowsError(
            try ShortURLResolver.redirectDecision(from: current, location: "file:///etc/passwd")
        )
    }
}
