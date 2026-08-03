import XCTest

@testable import LinkRouterCore

final class URLSanitizerTests: XCTestCase {
    func testOversizedInputIsLeftUntouched() throws {
        let oversized = "https://example.com/?utm_source=" + String(repeating: "x", count: 70_000)
        let input = try XCTUnwrap(URL(string: oversized))
        let result = URLSanitizer().sanitize(input)
        XCTAssertEqual(result.url, input)
        XCTAssertTrue(result.removedQueryItems.isEmpty)
    }

    func testRemovesGenericTrackingParameters() throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/article?id=42&utm_source=newsletter&fbclid=abc"))
        let result = URLSanitizer().sanitize(input)
        XCTAssertEqual(result.url.absoluteString, "https://example.com/article?id=42")
        XCTAssertEqual(Set(result.removedQueryItems), ["utm_source", "fbclid"])
    }

    func testUnwrapsFacebookRedirect() throws {
        let input = try XCTUnwrap(
            URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fx%3Futm_medium%3Dsocial"))
        let result = URLSanitizer().sanitize(input)
        XCTAssertEqual(result.url.absoluteString, "https://example.com/x")
        XCTAssertEqual(result.unwrappedRedirects.count, 1)
    }

    func testTikTokShareParameters() throws {
        let input = try XCTUnwrap(
            URL(string: "https://www.tiktok.com/@person/video/123?is_from_webapp=1&sender_device=pc&lang=en"))
        let result = URLSanitizer().sanitize(input)
        XCTAssertEqual(result.url.absoluteString, "https://www.tiktok.com/@person/video/123?lang=en")
    }

    func testPreservesGenericFunctionalParametersOnUnknownHosts() throws {
        let input = try XCTUnwrap(
            URL(
                string:
                    "https://example.com/action?checksum=abc&emailAddress=a%40b.com&product_id=42&message_id=7&utm_source=test"
            ))
        let result = URLSanitizer().sanitize(input)
        XCTAssertEqual(
            result.url.absoluteString,
            "https://example.com/action?checksum=abc&emailAddress=a%40b.com&product_id=42&message_id=7"
        )
        XCTAssertEqual(result.removedQueryItems, ["utm_source"])
    }

    func testDoesNotGuessRedirectsOnUnknownHosts() throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/about?url=https%3A%2F%2Fevil.example"))
        let result = URLSanitizer().sanitize(input)
        XCTAssertEqual(result.url, input)
        XCTAssertTrue(result.unwrappedRedirects.isEmpty)
    }

    func testHrefLiSupportsHTTPAndHTTPSWithoutFixedPrefixSlicing() throws {
        let destination = "https%3A%2F%2Fexample.com%2Farticle"
        for scheme in ["http", "https"] {
            let input = try XCTUnwrap(URL(string: "\(scheme)://href.li/?\(destination)"))
            XCTAssertEqual(
                RedirectUnwrapper().unwrap(input).url.absoluteString,
                "https://example.com/article"
            )
        }
    }
    func testCanUnwrapRedirectWithoutRemovingTrackingParameters() throws {
        let input = try XCTUnwrap(
            URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fx%3Futm_medium%3Dsocial%26id%3D42"))
        let result = URLSanitizer(removeTrackingParameters: false, unwrapRedirects: true).sanitize(input)
        XCTAssertEqual(result.url.absoluteString, "https://example.com/x?utm_medium=social&id=42")
        XCTAssertEqual(result.removedQueryItems, [])
        XCTAssertEqual(result.unwrappedRedirects.count, 1)
    }

    func testKeepsAmbiguousFunctionalParametersByDefault() throws {
        let input = try XCTUnwrap(
            URL(
                string:
                    "https://example.com/action?target=preview&language=en&signature=abc&context=editor&utm_source=test"
            ))
        let result = URLSanitizer().sanitize(input)
        XCTAssertEqual(
            result.url.absoluteString,
            "https://example.com/action?target=preview&language=en&signature=abc&context=editor"
        )
        XCTAssertEqual(result.removedQueryItems, ["utm_source"])
    }

}
