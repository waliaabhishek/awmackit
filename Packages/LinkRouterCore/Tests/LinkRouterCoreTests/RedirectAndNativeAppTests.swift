import XCTest

@testable import LinkRouterCore

final class RedirectAndNativeAppTests: XCTestCase {
    func testGoogleRedirect() throws {
        let input = try XCTUnwrap(URL(string: "https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fhello"))
        let result = RedirectUnwrapper().unwrap(input)
        XCTAssertEqual(result.url.absoluteString, "https://example.com/hello")
    }

    func testZoomTransform() throws {
        let definition = try XCTUnwrap(NativeAppCatalog.builtIns.first(where: { $0.id == "zoom" }))
        let input = try XCTUnwrap(URL(string: "https://acme.zoom.us/j/123456789?pwd=secret"))
        let output = try XCTUnwrap(definition.transformedURL(from: input))
        XCTAssertEqual(output.scheme, "zoommtg")
        XCTAssertTrue(output.absoluteString.contains("confno=123456789"))
    }

    func testSpotifyTransform() throws {
        let definition = try XCTUnwrap(NativeAppCatalog.builtIns.first(where: { $0.id == "spotify" }))
        let input = try XCTUnwrap(URL(string: "https://open.spotify.com/track/abc123?si=tracking"))
        XCTAssertEqual(definition.transformedURL(from: input)?.absoluteString, "spotify:track:abc123")
    }

    func testShortenerRegistryDistinguishesBuiltInFromCustomTrust() throws {
        let registry = ShortenerRegistry(customHosts: ["go.example.com"])
        let builtIn = try XCTUnwrap(URL(string: "https://BIT.LY/example"))
        let custom = try XCTUnwrap(URL(string: "https://go.example.com/example"))

        XCTAssertTrue(registry.containsBuiltIn(builtIn))
        XCTAssertTrue(registry.contains(custom))
        XCTAssertFalse(registry.containsBuiltIn(custom))
    }
}
