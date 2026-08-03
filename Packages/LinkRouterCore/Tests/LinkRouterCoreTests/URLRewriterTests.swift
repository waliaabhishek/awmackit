import XCTest

@testable import LinkRouterCore

final class URLRewriterTests: XCTestCase {
    func testReplaceHostPreservesPathQueryAndFragment() throws {
        let input = try XCTUnwrap(URL(string: "https://x.com/example/status/123?lang=en#replies"))
        let output = try StructuredURLRewriter().rewrite(
            input,
            actions: [URLRewriteAction(kind: .replaceHost, value: "xcancel.com")]
        )

        XCTAssertEqual(output.absoluteString, "https://xcancel.com/example/status/123?lang=en#replies")
    }

    func testStructuredActionsRunInOrder() throws {
        let input = try XCTUnwrap(URL(string: "http://example.com/old/page?utm_source=test&keep=yes"))
        let output = try StructuredURLRewriter().rewrite(
            input,
            actions: [
                URLRewriteAction(kind: .forceHTTPS),
                URLRewriteAction(kind: .replacePathPrefix, value: "/old", replacement: "/new"),
                URLRewriteAction(kind: .removeQueryParameters, value: "utm_source"),
                URLRewriteAction(kind: .setQueryParameter, value: "view", replacement: "compact"),
            ]
        )

        XCTAssertEqual(output.absoluteString, "https://example.com/new/page?keep=yes&view=compact")
    }

    func testInvalidReplacementHostIsRejected() throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/"))
        XCTAssertThrowsError(
            try StructuredURLRewriter().rewrite(
                input,
                actions: [URLRewriteAction(kind: .replaceHost, value: "not a host")]
            )
        )
    }
}
